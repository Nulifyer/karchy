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
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
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

	switch installerType {
	case "zip", "portable":
		return runZIP(path)
	case "msi", "wix":
		if elevate {
			return runElevated(path, installerType, silentArgs)
		}
		return runMSI(path, silentArgs)
	default:
		if elevate {
			return runElevated(path, installerType, silentArgs)
		}
		return runEXE(path, silentArgs)
	}
}

// runZIP extracts a ZIP archive to %LOCALAPPDATA%\Programs\<name>\ and adds it to the user PATH.
func runZIP(zipPath string) error {
	// Derive app name from the zip filename (e.g. "Microsoft.Sysinternals.Autoruns" → same)
	name := strings.TrimSuffix(filepath.Base(zipPath), filepath.Ext(zipPath))
	destDir := filepath.Join(os.Getenv("LOCALAPPDATA"), "Programs", name)

	logging.Info("runZIP: extracting %s -> %s", zipPath, destDir)

	// Clean out old version before extracting
	os.RemoveAll(destDir)
	if err := os.MkdirAll(destDir, 0755); err != nil {
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
			os.MkdirAll(target, 0755)
			continue
		}

		// Ensure parent directory exists
		os.MkdirAll(filepath.Dir(target), 0755)

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
		// Non-fatal — the files are extracted successfully
	}

	logging.Info("runZIP: extracted %d files to %s", len(r.File), destDir)
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

const userEnvKey = `Environment`

func openUserEnvKey() (registry.Key, error) {
	return registry.OpenKey(registry.CURRENT_USER, userEnvKey, registry.QUERY_VALUE|registry.SET_VALUE)
}

var (
	user32              = syscall.NewLazyDLL("user32.dll")
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
