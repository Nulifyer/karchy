//go:build windows

package install

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
	"golang.org/x/sys/windows/registry"
)

// DownloadFile downloads a URL to the karchy temp dir.
// If state is non-nil, it tracks progress via atomic DoneBytes.
// Returns the local file path.
func DownloadFile(url, name string, state *DownloadState) (string, error) {
	ext := filepath.Ext(name)
	if ext == "" {
		ext = ".exe"
	}

	tmpDir := filepath.Join(os.TempDir(), "karchy-install")
	os.MkdirAll(tmpDir, 0o755)
	tmpFile := filepath.Join(tmpDir, name)

	logging.Info("downloadFile: %s -> %s", url, tmpFile)

	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// Set total bytes for progress tracking
	if state != nil {
		state.TotalBytes = resp.ContentLength
	}

	f, err := os.Create(tmpFile)
	if err != nil {
		return "", err
	}
	defer f.Close()

	var w io.Writer = f
	if state != nil {
		w = &progressWriter{w: f, done: &state.DoneBytes}
	}

	written, err := io.Copy(w, resp.Body)
	if err != nil {
		os.Remove(tmpFile)
		return "", err
	}

	// Final update for progress
	if state != nil {
		atomic.StoreInt64(&state.DoneBytes, written)
		if state.TotalBytes <= 0 {
			state.TotalBytes = written // update from actual size when Content-Length was missing
		}
		state.Finished = true
	}

	logging.Info("downloadFile: %d bytes written", written)
	return tmpFile, nil
}

func VerifyHash(path, expectedHash string) error {
	if expectedHash == "" {
		logging.Info("verifyHash: no hash to verify, skipping")
		return nil
	}

	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return err
	}

	actual := strings.ToUpper(hex.EncodeToString(h.Sum(nil)))
	if actual != expectedHash {
		return fmt.Errorf("SHA256 mismatch: expected %s, got %s", expectedHash, actual)
	}

	logging.Info("verifyHash: SHA256 OK")
	return nil
}

func runInstaller(path, installerType, silentArgs string, pkg PackageEntry, elevate bool) error {
	logging.Info("runInstaller: type=%s args=%q elevate=%v", installerType, silentArgs, elevate)

	switch installerType {
	case "zip", "portable":
		return runZIP(path, pkg)
	default:
		return runShellExecute(path, installerType, silentArgs, elevate)
	}
}

// runZIP extracts a ZIP archive to %LOCALAPPDATA%\Programs\<name>\ and adds it to the user PATH.
func runZIP(zipPath string, pkg PackageEntry) error {
	name := pkg.ID
	destDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "Programs", name)

	logging.Info("runZIP: extracting %s -> %s", zipPath, destDir)

	// Clean out old version before extracting
	os.RemoveAll(destDir)
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return fmt.Errorf("create dest dir: %w", err)
	}

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("open zip: %w", err)
	}
	defer r.Close()

	for _, f := range r.File {
		// Prevent zip slip
		target := filepath.Join(destDir, f.Name)
		if !strings.HasPrefix(filepath.Clean(target), filepath.Clean(destDir)+string(os.PathSeparator)) && filepath.Clean(target) != filepath.Clean(destDir) {
			logging.Info("runZIP: skipping suspicious path %s", f.Name)
			continue
		}

		if f.FileInfo().IsDir() {
			os.MkdirAll(target, 0o755)
			continue
		}

		// Ensure parent directory exists
		os.MkdirAll(filepath.Dir(target), 0o755)

		out, err := os.Create(target)
		if err != nil {
			return fmt.Errorf("create %s: %w", f.Name, err)
		}

		rc, err := f.Open()
		if err != nil {
			out.Close()
			return fmt.Errorf("open %s in zip: %w", f.Name, err)
		}

		_, err = io.Copy(out, rc)
		rc.Close()
		out.Close()
		if err != nil {
			return fmt.Errorf("extract %s: %w", f.Name, err)
		}
	}

	// Add to user PATH if not already present
	if err := addToUserPath(destDir); err != nil {
		logging.Info("runZIP: failed to add to PATH: %v", err)
	}

	// Create Start Menu shortcuts for extracted .exe files
	if err := createStartMenuShortcuts(destDir, name); err != nil {
		logging.Info("runZIP: failed to create shortcuts: %v", err)
	}

	// Register in ARP so the package appears in Remove and can be uninstalled
	if err := registerZIPInARP(name, pkg.Name, destDir); err != nil {
		logging.Info("runZIP: failed to register in ARP: %v", err)
	}

	logging.Info("runZIP: extracted %d files to %s", len(r.File), destDir)
	return nil
}

// createStartMenuShortcuts creates .lnk files in the user's Start Menu for each .exe in dir.
// Cleans any existing shortcuts first so updates don't leave stale entries.
func createStartMenuShortcuts(dir, appName string) error {
	startMenu := filepath.Join(os.Getenv("APPDATA"), `Microsoft\Windows\Start Menu\Programs`, appName)
	os.RemoveAll(startMenu)

	// Find all .exe files in the extracted directory (top-level only)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}

	var exes []string
	for _, e := range entries {
		if !e.IsDir() && strings.EqualFold(filepath.Ext(e.Name()), ".exe") {
			exes = append(exes, filepath.Join(dir, e.Name()))
		}
	}
	if len(exes) == 0 {
		return nil
	}

	os.MkdirAll(startMenu, 0o755)

	for _, exePath := range exes {
		name := strings.TrimSuffix(filepath.Base(exePath), ".exe")
		lnkPath := filepath.Join(startMenu, name+".lnk")

		err := platform.CreateShortcut(platform.ShortcutOptions{
			LnkPath:     lnkPath,
			TargetPath:  exePath,
			WorkingDir:  dir,
			Description: name,
		})
		if err != nil {
			logging.Info("createStartMenuShortcuts: failed for %s: %v", name, err)
		} else {
			logging.Info("createStartMenuShortcuts: created %s", lnkPath)
		}
	}

	return nil
}

// registerZIPInARP creates/updates an ARP (Add/Remove Programs) registry entry so the
// ZIP-installed package appears in the system's installed programs list and in karchy's Remove menu.
// Uses a self-contained cmd uninstall command that doesn't depend on karchy.
func registerZIPInARP(id, displayName, installDir string) error {
	name := id
	arpPath := `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + name
	k, _, err := registry.CreateKey(registry.CURRENT_USER, arpPath, registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("create ARP key: %w", err)
	}
	defer k.Close()

	startMenu := filepath.Join(os.Getenv("APPDATA"), `Microsoft\Windows\Start Menu\Programs`, name)
	arpRegPath := `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + name

	// Self-contained uninstall: remove files, shortcuts, PATH entry, and ARP key
	uninstallCmd := fmt.Sprintf(
		`cmd /c rmdir /s /q "%s" & rmdir /s /q "%s" & reg delete "%s" /f & powershell -NoProfile -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); $new=($p -split ';' | Where-Object {$_ -ne '%s'}) -join ';'; [Environment]::SetEnvironmentVariable('Path',$new,'User')"`,
		installDir, startMenu, arpRegPath, installDir,
	)

	k.SetStringValue("DisplayName", displayName)
	k.SetStringValue("InstallLocation", installDir)
	k.SetStringValue("UninstallString", uninstallCmd)
	k.SetStringValue("QuietUninstallString", uninstallCmd)
	k.SetStringValue("Publisher", "Karchy (ZIP install)")
	k.SetDWordValue("NoModify", 1)
	k.SetDWordValue("NoRepair", 1)

	logging.Info("registerZIPInARP: registered %s", name)
	return nil
}

// addToUserPath adds a directory to the user-level PATH environment variable via the registry.
func addToUserPath(dir string) error {
	k, err := openUserEnvKey()
	if err != nil {
		return err
	}
	defer k.Close()

	current, _, err := k.GetStringValue("Path")
	if err != nil {
		current = ""
	}

	// Check if already in PATH (case-insensitive)
	for _, p := range strings.Split(current, ";") {
		if strings.EqualFold(strings.TrimSpace(p), dir) {
			logging.Info("addToUserPath: %s already in PATH", dir)
			return nil
		}
	}

	newPath := current
	if newPath != "" && !strings.HasSuffix(newPath, ";") {
		newPath += ";"
	}
	newPath += dir

	if err := k.SetStringValue("Path", newPath); err != nil {
		return fmt.Errorf("set PATH: %w", err)
	}

	// Broadcast WM_SETTINGCHANGE so Explorer picks up the new PATH
	broadcastSettingChange()

	logging.Info("addToUserPath: added %s to user PATH", dir)
	return nil
}

// runShellExecute uses ShellExecuteExW to launch any installer type.
// This matches winget's behavior: ShellExecuteEx handles embedded application
// manifests (elevatesSelf) and UAC prompts correctly, unlike CreateProcessW.
// When elevate is true, the "runas" verb triggers a UAC prompt.
// When elevate is false, the "open" verb lets Windows handle elevation
// based on the installer's own embedded manifest.
func runShellExecute(path, installerType, silentArgs string, elevate bool) error {
	var file, params string

	switch installerType {
	case "msi", "wix":
		file = "msiexec"
		params = "/i " + `"` + path + `"`
		if silentArgs != "" {
			params += " " + silentArgs
		}
	default:
		file = path
		params = silentArgs
	}

	verb := "open"
	if elevate {
		verb = "runas"
	}

	logging.Info("runShellExecute: verb=%s file=%s params=%s", verb, file, params)

	filePtr, _ := syscall.UTF16PtrFromString(file)
	paramsPtr, _ := syscall.UTF16PtrFromString(params)
	verbPtr, _ := syscall.UTF16PtrFromString(verb)

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

	// Wait for the installer to finish
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

	switch exitCode {
	case 0:
		// success
	case 3010, 1641:
		// 3010 = reboot required, 1641 = reboot initiated — treat as success
		logging.Info("runShellExecute: success (exit code %d — reboot required)", exitCode)
	case 1614:
		// product uninstalled (upgrade scenarios) — treat as success
		logging.Info("runShellExecute: success (exit code %d — product uninstalled for upgrade)", exitCode)
	default:
		return fmt.Errorf("installer exited with code %d", exitCode)
	}

	logging.Info("runShellExecute: success")
	return nil
}

type shellExecuteInfo struct {
	cbSize         uint32
	fMask          uint32
	hwnd           uintptr
	lpVerb         *uint16
	lpFile         *uint16
	lpParameters   *uint16
	lpDirectory    *uint16
	nShow          int32
	hInstApp       uintptr
	lpIDList       uintptr
	lpClass        *uint16
	hkeyClass      uintptr
	dwHotKey       uint32
	hIconOrMonitor uintptr
	hProcess       uintptr
}

var (
	shell32          = syscall.NewLazyDLL("shell32.dll")
	procShellExecute = shell32.NewProc("ShellExecuteExW")
)

func shellExecuteEx(info *shellExecuteInfo) error {
	ret, _, err := procShellExecute.Call(uintptr(unsafe.Pointer(info)))
	if ret == 0 {
		return err
	}
	return nil
}

const userEnvKey = `Environment`

func openUserEnvKey() (registry.Key, error) {
	return registry.OpenKey(registry.CURRENT_USER, userEnvKey, registry.QUERY_VALUE|registry.SET_VALUE)
}

var (
	user32                 = syscall.NewLazyDLL("user32.dll")
	procSendMessageTimeout = user32.NewProc("SendMessageTimeoutW")
)

func broadcastSettingChange() {
	env, _ := syscall.UTF16PtrFromString("Environment")
	// HWND_BROADCAST=0xFFFF, WM_SETTINGCHANGE=0x001A, SMTO_ABORTIFHUNG=0x0002, timeout=5000ms
	procSendMessageTimeout.Call(
		uintptr(0xFFFF),
		uintptr(0x001A),
		0,
		uintptr(unsafe.Pointer(env)),
		uintptr(0x0002),
		uintptr(5000),
		0,
	)
}
