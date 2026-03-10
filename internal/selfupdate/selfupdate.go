package selfupdate

import (
	"archive/tar"
	"archive/zip"
	"compress/gzip"
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
// Returns true if an update was applied.
func Run(currentVersion string) bool {
	fmt.Println("Checking for updates...")

	rel, err := fetchLatest()
	if err != nil {
		fmt.Printf("Failed to check for updates: %v\n", err)
		os.Exit(1)
	}

	if rel.TagName == currentVersion || rel.TagName == "v"+currentVersion {
		fmt.Println("Already up to date (" + currentVersion + ").")
		return false
	}

	// GoReleaser archives: karchy_<version>_<os>_<arch>.<ext>
	version := strings.TrimPrefix(rel.TagName, "v")
	archiveName := archiveName(version)
	var downloadURL string
	for _, a := range rel.Assets {
		if a.Name == archiveName {
			downloadURL = a.BrowserDownloadURL
			break
		}
	}
	if downloadURL == "" {
		fmt.Printf("No release asset found for %s in %s\n", archiveName, rel.TagName)
		os.Exit(1)
	}

	fmt.Printf("Updating %s → %s...\n", currentVersion, rel.TagName)
	if err := downloadAndExtract(downloadURL); err != nil {
		fmt.Printf("Update failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Updated to " + rel.TagName + "!")
	return true
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

func archiveName(version string) string {
	if runtime.GOOS == "windows" {
		return fmt.Sprintf("karchy_%s_%s_%s.zip", version, runtime.GOOS, runtime.GOARCH)
	}
	return fmt.Sprintf("karchy_%s_%s_%s.tar.gz", version, runtime.GOOS, runtime.GOARCH)
}

func binaryNameInArchive() string {
	if runtime.GOOS == "windows" {
		return "karchy.exe"
	}
	return "karchy"
}

func downloadAndExtract(url string) error {
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

	dir := filepath.Dir(exePath)
	tmp, err := os.CreateTemp(dir, "karchy-update-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()

	// Download archive to temp file
	_, err = io.Copy(tmp, resp.Body)
	tmp.Close()
	if err != nil {
		os.Remove(tmpPath)
		return err
	}

	// Extract binary from archive
	binaryTmp, err := os.CreateTemp(dir, "karchy-bin-*")
	if err != nil {
		os.Remove(tmpPath)
		return err
	}
	binaryPath := binaryTmp.Name()
	binaryTmp.Close()

	target := binaryNameInArchive()
	if runtime.GOOS == "windows" {
		err = extractFromZip(tmpPath, target, binaryPath)
	} else {
		err = extractFromTarGz(tmpPath, target, binaryPath)
	}
	os.Remove(tmpPath) // clean up archive
	if err != nil {
		os.Remove(binaryPath)
		return err
	}

	return replaceBinary(exePath, binaryPath)
}

func extractFromTarGz(archivePath, target, destPath string) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		if filepath.Base(hdr.Name) == target {
			out, err := os.Create(destPath)
			if err != nil {
				return err
			}
			_, err = io.Copy(out, tr)
			out.Close()
			return err
		}
	}
	return fmt.Errorf("binary %q not found in archive", target)
}

func extractFromZip(archivePath, target, destPath string) error {
	r, err := zip.OpenReader(archivePath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		if filepath.Base(f.Name) == target {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			out, err := os.Create(destPath)
			if err != nil {
				rc.Close()
				return err
			}
			_, err = io.Copy(out, rc)
			out.Close()
			rc.Close()
			return err
		}
	}
	return fmt.Errorf("binary %q not found in archive", target)
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
		return nil
	}

	// Unix: atomic rename
	if err := os.Chmod(tmpPath, 0o755); err != nil {
		os.Remove(tmpPath)
		return err
	}
	if err := os.Rename(tmpPath, exePath); err != nil {
		os.Remove(tmpPath)
		return err
	}
	return nil
}

// CheckAvailable returns the latest release tag if a newer version is available,
// or an empty string if already up to date (or on error).
func CheckAvailable(currentVersion string) string {
	rel, err := fetchLatest()
	if err != nil {
		return ""
	}
	if rel.TagName == currentVersion || rel.TagName == "v"+currentVersion {
		return ""
	}
	return rel.TagName
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
	if resolved, err := filepath.EvalSymlinks(exePath); err == nil {
		os.Remove(resolved + ".old")
	}
	os.Remove(oldPath)
}
