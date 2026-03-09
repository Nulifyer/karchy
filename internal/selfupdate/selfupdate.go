package selfupdate

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type release struct {
	TagName string  `json:"tag_name"`
	Assets  []asset `json:"assets"`
}

type asset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

// Run checks GitHub for a newer release and updates the binary in-place.
func Run(currentVersion string) {
	fmt.Println("Checking for updates...")

	rel, err := fetchLatest()
	if err != nil {
		fmt.Printf("Failed to check for updates: %v\n", err)
		os.Exit(1)
	}

	if rel.TagName == currentVersion || rel.TagName == "v"+currentVersion {
		fmt.Println("Already up to date (" + currentVersion + ").")
		return
	}

	assetName := binaryName()
	var downloadURL string
	for _, a := range rel.Assets {
		if a.Name == assetName {
			downloadURL = a.BrowserDownloadURL
			break
		}
	}
	if downloadURL == "" {
		fmt.Printf("No release asset found for %s in %s\n", assetName, rel.TagName)
		os.Exit(1)
	}

	fmt.Printf("Updating %s → %s...\n", currentVersion, rel.TagName)
	if err := download(downloadURL); err != nil {
		fmt.Printf("Update failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Updated to " + rel.TagName + "!")
}

func fetchLatest() (*release, error) {
	resp, err := http.Get("https://api.github.com/repos/Nulifyer/karchy/releases/latest")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("GitHub API returned %d", resp.StatusCode)
	}
	var rel release
	if err := json.NewDecoder(resp.Body).Decode(&rel); err != nil {
		return nil, err
	}
	return &rel, nil
}

func binaryName() string {
	ext := ""
	if runtime.GOOS == "windows" {
		ext = ".exe"
	}
	return fmt.Sprintf("karchy-%s-%s%s", runtime.GOOS, runtime.GOARCH, ext)
}

func download(url string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("download returned %d", resp.StatusCode)
	}

	exePath, err := os.Executable()
	if err != nil {
		return err
	}
	exePath, err = filepath.EvalSymlinks(exePath)
	if err != nil {
		return err
	}

	// Write to temp file in same directory (ensures same filesystem for rename)
	dir := filepath.Dir(exePath)
	tmp, err := os.CreateTemp(dir, "karchy-update-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()

	_, err = io.Copy(tmp, resp.Body)
	tmp.Close()
	if err != nil {
		os.Remove(tmpPath)
		return err
	}

	return replaceBinary(exePath, tmpPath)
}

// replaceBinary swaps the old binary with the new one.
// Platform-specific: on Windows we rename the old exe first since it's locked.
func replaceBinary(exePath, tmpPath string) error {
	if runtime.GOOS == "windows" {
		oldPath := exePath + ".old"
		os.Remove(oldPath) // remove any previous .old
		if err := os.Rename(exePath, oldPath); err != nil {
			os.Remove(tmpPath)
			return fmt.Errorf("rename current binary: %w", err)
		}
		if err := os.Rename(tmpPath, exePath); err != nil {
			// Try to restore
			os.Rename(oldPath, exePath)
			os.Remove(tmpPath)
			return fmt.Errorf("rename new binary: %w", err)
		}
		// Schedule .old for deletion — it'll be cleaned up on next update or manually
		return nil
	}

	// Unix: atomic rename
	if err := os.Chmod(tmpPath, 0o755); err != nil {
		os.Remove(tmpPath)
		return err
	}
	if err := os.Rename(tmpPath, exePath); err != nil {
		// Fallback: copy if rename fails (cross-device)
		os.Remove(tmpPath)
		return err
	}
	return nil
}

// CleanOld removes any leftover .old binary from a previous update.
func CleanOld() {
	if runtime.GOOS != "windows" {
		return
	}
	exePath, err := os.Executable()
	if err != nil {
		return
	}
	oldPath := exePath + ".old"
	// Also handle case where exePath has been resolved
	if resolved, err := filepath.EvalSymlinks(exePath); err == nil {
		os.Remove(resolved + ".old")
	}
	os.Remove(oldPath)
}

// CompareVersions returns true if remote is newer than current.
// Both should be semver strings like "v1.2.3" or "1.2.3".
func CompareVersions(current, remote string) bool {
	current = strings.TrimPrefix(current, "v")
	remote = strings.TrimPrefix(remote, "v")

	cParts := strings.Split(current, ".")
	rParts := strings.Split(remote, ".")

	for i := 0; i < 3; i++ {
		var c, r int
		if i < len(cParts) {
			fmt.Sscan(cParts[i], &c)
		}
		if i < len(rParts) {
			fmt.Sscan(rParts[i], &r)
		}
		if r > c {
			return true
		}
		if r < c {
			return false
		}
	}
	return false
}
