package webapp

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"image"
	"image/draw"
	"image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nulifyer/karchy/internal/logging"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

const dashboardIconsRepo = "homarr-labs/dashboard-icons"

// iconSource represents the user's choice for icon sourcing.
type iconSource int

const (
	iconDashboard iconSource = iota
	iconFavicon
	iconManual
)

// DashboardIcon represents an entry from the dashboard-icons metadata.
type DashboardIcon struct {
	Name        string // slug name (e.g. "home-assistant")
	DisplayName string // title-cased name
}

// LoadDashboardIcons fetches the metadata.json from homarr-labs/dashboard-icons.
func LoadDashboardIcons() ([]DashboardIcon, string, error) {
	cacheDir := filepath.Join(os.TempDir(), "karchy-dashboard-icons")
	metaPath := filepath.Join(cacheDir, "metadata.json")
	commitPath := filepath.Join(cacheDir, "commit.txt")

	// Check for latest commit
	commit := getLatestCommit()
	cached := ""
	if data, err := os.ReadFile(commitPath); err == nil {
		cached = strings.TrimSpace(string(data))
	}

	if commit != "" && commit != cached {
		os.MkdirAll(cacheDir, 0o755)
		metaURL := fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/metadata.json", dashboardIconsRepo, commit)
		if err := downloadFile(metaURL, metaPath); err != nil {
			if cached == "" {
				return nil, "", fmt.Errorf("failed to fetch icon metadata: %w", err)
			}
			// Use stale cache
			commit = cached
		} else {
			os.WriteFile(commitPath, []byte(commit), 0o644)
		}
	} else if commit == "" {
		commit = cached
	}

	if commit == "" {
		return nil, "", fmt.Errorf("no icon metadata available")
	}

	// Parse metadata
	data, err := os.ReadFile(metaPath)
	if err != nil {
		return nil, "", err
	}

	var meta map[string]json.RawMessage
	if err := json.Unmarshal(data, &meta); err != nil {
		return nil, "", err
	}

	icons := make([]DashboardIcon, 0, len(meta))
	for name := range meta {
		display := strings.ReplaceAll(name, "-", " ")
		display = cases.Title(language.English).String(display)
		icons = append(icons, DashboardIcon{Name: name, DisplayName: display})
	}

	return icons, commit, nil
}

// DashboardIconURL returns the CDN URL for a dashboard icon.
// Uses SVG on platforms that support it, PNG otherwise.
func DashboardIconURL(commit, iconName string) string {
	return fmt.Sprintf("https://cdn.jsdelivr.net/gh/%s@%s/%s/%s.%s", dashboardIconsRepo, commit, dashboardIconFmt, iconName, dashboardIconFmt)
}

// FaviconURL returns the best available favicon URL for a site.
// It tries the site's apple-touch-icon (usually 180x180) first,
// then falls back to the Google favicon service.
func FaviconURL(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	domain := u.Hostname()
	if domain == "" {
		domain = rawURL
	}

	// Try apple-touch-icon first (typically 180x180)
	touchIcon := fmt.Sprintf("%s://%s/apple-touch-icon.png", u.Scheme, u.Host)
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Head(touchIcon)
	if err == nil {
		resp.Body.Close()
		if resp.StatusCode == http.StatusOK {
			ct := resp.Header.Get("Content-Type")
			if strings.HasPrefix(ct, "image/") {
				return touchIcon
			}
		}
	}

	return fmt.Sprintf("https://www.google.com/s2/favicons?domain=%s&sz=256", domain)
}

// DownloadIcon downloads an icon from a URL and saves it to the icon directory.
// On Windows, converts to .ico format. Returns the saved icon path.
func DownloadIcon(id, iconURL string) (string, error) {
	iconDir := IconDir()
	if err := os.MkdirAll(iconDir, 0o755); err != nil {
		return "", fmt.Errorf("create icon dir: %w", err)
	}

	tmpPath := filepath.Join(iconDir, id+".tmp")
	defer os.Remove(tmpPath)

	if err := downloadFile(iconURL, tmpPath); err != nil {
		return "", fmt.Errorf("download icon: %w", err)
	}

	return convertIcon(id, tmpPath, iconURL)
}

func getLatestCommit() string {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(fmt.Sprintf("https://api.github.com/repos/%s/commits/main", dashboardIconsRepo))
	if err != nil {
		logging.Info("getLatestCommit: %v", err)
		return ""
	}
	defer resp.Body.Close()

	var result struct {
		SHA string `json:"sha"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return ""
	}
	if len(result.SHA) >= 7 {
		return result.SHA[:7]
	}
	return result.SHA
}

func downloadFile(url, dest string) error {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}

// pngToICO decodes PNG data, pads to square if needed, and wraps in an ICO container.
func pngToICO(pngData []byte, icoPath string) error {
	img, err := png.Decode(bytes.NewReader(pngData))
	if err != nil {
		return fmt.Errorf("decode PNG: %w", err)
	}

	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()

	// Pad to square if non-square
	if w != h {
		size := w
		if h > size {
			size = h
		}
		square := image.NewRGBA(image.Rect(0, 0, size, size))
		ox := (size - w) / 2
		oy := (size - h) / 2
		draw.Draw(square, image.Rect(ox, oy, ox+w, oy+h), img, bounds.Min, draw.Over)
		img = square
		w, h = size, size
	}

	// Re-encode as PNG
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return fmt.Errorf("encode PNG: %w", err)
	}
	pngData = buf.Bytes()

	// ICO dimension byte: 0 means 256+
	dimByte := func(d int) byte {
		if d >= 256 {
			return 0
		}
		return byte(d)
	}

	f, err := os.Create(icoPath)
	if err != nil {
		return err
	}
	defer f.Close()

	// Write ICO via a buffer so partial writes don't corrupt the file.
	var ico bytes.Buffer

	// ICO header: reserved(2) + type=1(2) + count=1(2)
	binary.Write(&ico, binary.LittleEndian, uint16(0)) // reserved
	binary.Write(&ico, binary.LittleEndian, uint16(1)) // type: icon
	binary.Write(&ico, binary.LittleEndian, uint16(1)) // count

	// Directory entry
	ico.Write([]byte{dimByte(w)})                                 // width
	ico.Write([]byte{dimByte(h)})                                 // height
	ico.Write([]byte{0})                                          // color palette
	ico.Write([]byte{0})                                          // reserved
	binary.Write(&ico, binary.LittleEndian, uint16(1))            // planes
	binary.Write(&ico, binary.LittleEndian, uint16(32))           // bpp
	binary.Write(&ico, binary.LittleEndian, uint32(len(pngData))) // data size
	binary.Write(&ico, binary.LittleEndian, uint32(22))           // data offset (6 header + 16 entry)

	// PNG data
	ico.Write(pngData)

	_, err = f.Write(ico.Bytes())
	return err
}
