//go:build windows

package install

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
)

// DirectInstall fetches the manifest, downloads the installer, verifies the hash,
// and runs it with silent switches — no winget CLI needed.
func DirectInstall(pkg PackageEntry) error {
	logging.Info("DirectInstall: %s (%s) v%s", pkg.Name, pkg.ID, pkg.Version)

	manifest, err := FetchManifest(pkg.ID, pkg.Version)
	if err != nil {
		return fmt.Errorf("manifest: %w", err)
	}

	entry, err := SelectInstaller(manifest)
	if err != nil {
		return fmt.Errorf("select installer: %w", err)
	}
	logging.Info("DirectInstall: selected %s %s %s", entry.Architecture, entry.Scope, entry.EffectiveType(manifest))

	installerPath, err := DownloadFile(entry.InstallerURL, fileNameFromURL(entry.InstallerURL), nil)
	if err != nil {
		return fmt.Errorf("download: %w", err)
	}
	defer os.Remove(installerPath)

	if err := VerifyHash(installerPath, entry.SHA256); err != nil {
		return fmt.Errorf("hash verification: %w", err)
	}

	args := SilentArgs(manifest, entry)
	return runInstaller(installerPath, entry.EffectiveType(manifest), args, entry.NeedsElevation(manifest))
}

// downloadFile downloads a URL to the karchy temp dir.
// If state is non-nil, it tracks progress via atomic DoneBytes.
// Returns the local file path.
func DownloadFile(url, name string, state *DownloadState) (string, error) {
	ext := filepath.Ext(name)
	if ext == "" {
		ext = ".exe"
	}

	tmpDir := filepath.Join(os.TempDir(), "karchy-install")
	os.MkdirAll(tmpDir, 0755)
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

func fileNameFromURL(url string) string {
	if idx := strings.LastIndex(url, "/"); idx >= 0 {
		name := url[idx+1:]
		// Strip query params
		if qi := strings.Index(name, "?"); qi >= 0 {
			name = name[:qi]
		}
		if name != "" {
			return name
		}
	}
	return "installer.exe"
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

func runInstaller(path, installerType, silentArgs string, elevate bool) error {
	logging.Info("runInstaller: type=%s args=%q elevate=%v", installerType, silentArgs, elevate)

	if elevate {
		return runElevated(path, installerType, silentArgs)
	}

	switch installerType {
	case "msi", "wix":
		return runMSI(path, silentArgs)
	default:
		return runEXE(path, silentArgs)
	}
}

func runEXE(path, args string) error {
	var argv []string
	if args != "" {
		argv = strings.Fields(args)
	}

	cmd := exec.Command(path, argv...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard

	logging.Info("runEXE: %s %v", path, argv)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("installer exited with error: %w", err)
	}
	return nil
}

func runMSI(path, args string) error {
	argv := []string{"/i", path}
	if args != "" {
		argv = append(argv, strings.Fields(args)...)
	}

	cmd := exec.Command("msiexec", argv...)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard

	logging.Info("runMSI: msiexec %v", argv)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("msiexec exited with error: %w", err)
	}
	return nil
}

// runElevated uses ShellExecuteEx with "runas" to trigger a UAC prompt.
func runElevated(path, installerType, silentArgs string) error {
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

	logging.Info("runElevated: runas %s %s", file, params)

	filePtr, _ := syscall.UTF16PtrFromString(file)
	paramsPtr, _ := syscall.UTF16PtrFromString(params)
	verbPtr, _ := syscall.UTF16PtrFromString("runas")

	info := &shellExecuteInfo{
		cbSize: uint32(unsafe.Sizeof(shellExecuteInfo{})),
		fMask:  0x00000040, // SEE_MASK_NOCLOSEPROCESS
		lpVerb: verbPtr,
		lpFile: filePtr,
		lpParameters: paramsPtr,
		nShow:  0, // SW_HIDE
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
	if exitCode != 0 {
		return fmt.Errorf("installer exited with code %d", exitCode)
	}

	logging.Info("runElevated: success")
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
