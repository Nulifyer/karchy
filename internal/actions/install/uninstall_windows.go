//go:build windows

package install

import (
	"bufio"
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
	"golang.org/x/sys/windows/registry"
)

// InstalledPackage represents a package that can be uninstalled.
type InstalledPackage struct {
	Name                 string
	ID                   string // winget package ID (if matched)
	Version              string
	Publisher            string
	UninstallString      string
	QuietUninstallString string
	IsWindowsInstaller   bool // MSI package (WindowsInstaller DWORD = 1)
	RegistryKey          string
	RegistryRoot         registry.Key
}

// InstalledPackages returns all removable packages from the ARP registry,
// enriched with winget package IDs where possible.
func InstalledPackages() []InstalledPackage {
	// Build product code -> package ID map from winget source index
	pcToID := make(map[string]string)
	if srcPath := findSourceIndex(); srcPath != "" {
		pcToID = loadProductCodeMap(srcPath)
	}

	// Scan ARP registry
	arpPaths := []struct {
		root registry.Key
		path string
	}{
		{registry.LOCAL_MACHINE, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
		{registry.LOCAL_MACHINE, `SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`},
		{registry.CURRENT_USER, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
	}

	seen := make(map[string]bool)
	var pkgs []InstalledPackage

	for _, arp := range arpPaths {
		key, err := registry.OpenKey(arp.root, arp.path, registry.ENUMERATE_SUB_KEYS)
		if err != nil {
			continue
		}
		subkeys, err := key.ReadSubKeyNames(-1)
		key.Close()
		if err != nil {
			continue
		}

		for _, sk := range subkeys {
			if seen[sk] {
				continue
			}
			seen[sk] = true

			entry := readARPEntry(arp.root, arp.path+`\`+sk)
			if entry == nil {
				continue
			}
			entry.RegistryKey = sk
			entry.RegistryRoot = arp.root

			// Try to match winget ID via product code
			if id, ok := pcToID[strings.ToLower(sk)]; ok {
				entry.ID = id
			}

			pkgs = append(pkgs, *entry)
		}
	}

	logging.Info("InstalledPackages: %d removable packages", len(pkgs))
	return pkgs
}

// readARPEntry reads an ARP registry entry and returns an InstalledPackage.
// Returns nil if the entry should be skipped (system component, no name, no uninstall string).
func readARPEntry(root registry.Key, path string) *InstalledPackage {
	key, err := registry.OpenKey(root, path, registry.QUERY_VALUE)
	if err != nil {
		return nil
	}
	defer key.Close()

	// Skip system components
	if val, _, err := key.GetIntegerValue("SystemComponent"); err == nil && val == 1 {
		return nil
	}
	// Skip sub-components
	if val, _, err := key.GetStringValue("ParentKeyName"); err == nil && val != "" {
		return nil
	}

	name, _, _ := key.GetStringValue("DisplayName")
	if name == "" {
		return nil
	}

	uninstall, _, _ := key.GetStringValue("UninstallString")
	quietUninstall, _, _ := key.GetStringValue("QuietUninstallString")

	// Must have at least one uninstall method
	if uninstall == "" && quietUninstall == "" {
		return nil
	}

	version, _, _ := key.GetStringValue("DisplayVersion")
	publisher, _, _ := key.GetStringValue("Publisher")

	isWindowsInstaller := false
	if val, _, err := key.GetIntegerValue("WindowsInstaller"); err == nil && val == 1 {
		isWindowsInstaller = true
	}

	return &InstalledPackage{
		Name:                 name,
		Version:              version,
		Publisher:            publisher,
		UninstallString:      uninstall,
		QuietUninstallString: quietUninstall,
		IsWindowsInstaller:   isWindowsInstaller,
	}
}

// loadProductCodeMap builds a product code -> package ID map from the winget source index.
func loadProductCodeMap(sourceDBPath string) map[string]string {
	db, err := sql.Open("sqlite", sourceDBPath+"?mode=ro")
	if err != nil {
		logging.Info("loadProductCodeMap: open failed: %v", err)
		return nil
	}
	defer db.Close()

	rows, err := db.Query("SELECT pc.productcode, p.id FROM productcodes2 pc JOIN packages p ON p.rowid = pc.package")
	if err != nil {
		logging.Info("loadProductCodeMap: query failed: %v", err)
		return nil
	}
	defer rows.Close()

	m := make(map[string]string)
	for rows.Next() {
		var pc, id string
		if err := rows.Scan(&pc, &id); err != nil {
			continue
		}
		m[strings.ToLower(pc)] = id
	}
	logging.Info("loadProductCodeMap: %d product codes", len(m))
	return m
}

// UninstallPackage silently uninstalls a single package.
func UninstallPackage(pkg InstalledPackage) error {
	logging.Info("UninstallPackage: %s (key=%s)", pkg.Name, pkg.RegistryKey)

	// Strategy 1: Karchy ZIP install — run cmd directly (no elevation needed, user-level)
	if pkg.Publisher == "Karchy (ZIP install)" {
		uninstall := pkg.QuietUninstallString
		if uninstall == "" {
			uninstall = pkg.UninstallString
		}
		if uninstall == "" {
			return fmt.Errorf("no uninstall method available")
		}
		exe, args := parseUninstallString(uninstall)
		logging.Info("UninstallPackage: karchy ZIP uninstall exe=%s args=%s", exe, args)
		return runUnelevatedUninstall(exe, args)
	}

	// Strategy 2: MSI — use msiexec /x with the product code
	if pkg.IsWindowsInstaller {
		return uninstallMSI(pkg)
	}

	// Strategy 3: QuietUninstallString — already has silent flags
	if pkg.QuietUninstallString != "" {
		return runUninstallString(pkg.QuietUninstallString)
	}

	// Strategy 4: UninstallString
	if pkg.UninstallString != "" {
		return runUninstallString(pkg.UninstallString)
	}

	return fmt.Errorf("no uninstall method available")
}

func uninstallMSI(pkg InstalledPackage) error {
	// Extract product code — prefer registry key if it's a GUID
	productCode := pkg.RegistryKey
	if !strings.HasPrefix(productCode, "{") {
		// Try to extract from UninstallString: MsiExec.exe /X{GUID}
		if idx := strings.Index(pkg.UninstallString, "{"); idx >= 0 {
			end := strings.Index(pkg.UninstallString[idx:], "}")
			if end >= 0 {
				productCode = pkg.UninstallString[idx : idx+end+1]
			}
		}
	}

	params := fmt.Sprintf("/x %s /quiet /norestart", productCode)
	logging.Info("uninstallMSI: msiexec %s", params)
	return runElevatedUninstall("msiexec", params)
}

func runUninstallString(uninstallStr string) error {
	exe, args := parseUninstallString(uninstallStr)
	if exe == "" {
		return fmt.Errorf("could not parse uninstall string: %s", uninstallStr)
	}

	logging.Info("runUninstallString: exe=%s args=%s", exe, args)
	return runElevatedUninstall(exe, args)
}

// parseUninstallString splits an uninstall string into executable path and arguments.
// Handles quoted paths like: "C:\Program Files\App\unins000.exe" /SILENT
func parseUninstallString(s string) (exe, args string) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", ""
	}

	if s[0] == '"' {
		// Quoted path
		end := strings.Index(s[1:], `"`)
		if end < 0 {
			return s[1:], ""
		}
		exe = s[1 : end+1]
		args = strings.TrimSpace(s[end+2:])
		return exe, args
	}

	// Unquoted — split on first space after .exe
	lower := strings.ToLower(s)
	if idx := strings.Index(lower, ".exe "); idx >= 0 {
		return s[:idx+4], strings.TrimSpace(s[idx+5:])
	}
	if idx := strings.Index(lower, ".exe"); idx >= 0 {
		return s[:idx+4], ""
	}

	// No .exe found — could be msiexec or similar
	parts := strings.SplitN(s, " ", 2)
	if len(parts) == 2 {
		return parts[0], parts[1]
	}
	return s, ""
}

// runUnelevatedUninstall runs an uninstall command without elevation (for user-level installs).
// Uses cmd /c with the full command to preserve quoted paths.
func runUnelevatedUninstall(file, params string) error {
	full := file
	if params != "" {
		full += " " + params
	}
	logging.Info("runUnelevatedUninstall: cmd /c %s", full)

	cmd := exec.Command("cmd", "/c", full)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("uninstall command failed: %w", err)
	}

	logging.Info("runUnelevatedUninstall: success")
	return nil
}

// runElevatedUninstall uses ShellExecuteEx with "runas" to run an uninstall command.
func runElevatedUninstall(file, params string) error {
	logging.Info("runElevatedUninstall: runas %s %s", file, params)

	filePtr, _ := syscall.UTF16PtrFromString(file)
	paramsPtr, _ := syscall.UTF16PtrFromString(params)
	verbPtr, _ := syscall.UTF16PtrFromString("runas")

	info := &shellExecuteInfo{
		cbSize:       uint32(unsafe.Sizeof(shellExecuteInfo{})),
		fMask:        0x00000040, // SEE_MASK_NOCLOSEPROCESS
		lpVerb:       verbPtr,
		lpFile:       filePtr,
		lpParameters: paramsPtr,
		nShow:        0, // SW_HIDE
	}

	if err := shellExecuteEx(info); err != nil {
		return fmt.Errorf("ShellExecuteEx: %w", err)
	}
	if info.hProcess == 0 {
		return fmt.Errorf("ShellExecuteEx: no process handle returned")
	}
	defer syscall.CloseHandle(syscall.Handle(info.hProcess))

	event, err := syscall.WaitForSingleObject(syscall.Handle(info.hProcess), syscall.INFINITE)
	if err != nil {
		return fmt.Errorf("WaitForSingleObject: %w", err)
	}
	if event != syscall.WAIT_OBJECT_0 {
		return fmt.Errorf("unexpected wait result: %d", event)
	}

	var exitCode uint32
	if err := syscall.GetExitCodeProcess(syscall.Handle(info.hProcess), &exitCode); err != nil {
		return fmt.Errorf("GetExitCodeProcess: %w", err)
	}
	if exitCode != 0 {
		return fmt.Errorf("uninstaller exited with code %d", exitCode)
	}

	logging.Info("runElevatedUninstall: success")
	return nil
}

// BatchUninstall removes multiple packages with progress display.
func BatchUninstall(pkgs []InstalledPackage) {
	if len(pkgs) == 0 {
		return
	}

	restoreVT := enableVT()
	defer restoreVT()

	// List packages and confirm
	fmt.Printf("\n Packages (%d)\n\n", len(pkgs))
	for _, pkg := range pkgs {
		if pkg.Version != "" && !strings.Contains(pkg.Name, pkg.Version) {
			fmt.Printf(" %s  %s%s%s\n", pkg.Name, colorGreen, pkg.Version, colorReset)
		} else {
			fmt.Printf(" %s\n", pkg.Name)
		}
	}

	fmt.Printf("\n %s%s:: Proceed with removal? [Y/n]%s ", colorBold, colorCyan, colorReset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	fmt.Printf("\n %s%s:: Removing packages...%s\n\n", colorBold, colorCyan, colorReset)

	var removed, failed int
	var failures []string

	for i, pkg := range pkgs {
		fmt.Printf(" [%d/%d] Removing %s...", i+1, len(pkgs), pkg.Name)

		err := UninstallPackage(pkg)
		if err != nil {
			fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
			failed++
			failures = append(failures, fmt.Sprintf("%s: %v", pkg.Name, err))
		} else {
			fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
			removed++
		}
	}

	// Summary
	fmt.Println()
	if failed == 0 {
		fmt.Printf(" %s%s:: %d package(s) removed successfully.%s\n\n",
			colorBold, colorGreen, removed, colorReset)
	} else {
		fmt.Printf(" %s%s:: %d removed, %d failed:%s\n",
			colorBold, colorRed, removed, failed, colorReset)
		for _, f := range failures {
			fmt.Printf("    %s- %s%s\n", colorRed, f, colorReset)
		}
		fmt.Println()
	}

	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}
