package install

import (
	"fmt"
	"io"
	"strings"
	"sync/atomic"
	"time"
)

// progressWriter wraps an io.Writer and atomically tracks bytes written.
type progressWriter struct {
	w    io.Writer
	done *int64
}

func (pw *progressWriter) Write(p []byte) (int, error) {
	n, err := pw.w.Write(p)
	atomic.AddInt64(pw.done, int64(n))
	return n, err
}

// DownloadState tracks a single download's progress.
type DownloadState struct {
	Name       string // display filename
	TotalBytes int64  // from Content-Length, -1 if unknown
	DoneBytes  int64  // updated atomically by progressWriter
	StartTime  time.Time
	Active     bool // set when download actually starts (acquired semaphore)
	Finished   bool
	Err        error
}

// renderLine draws a single pacman-style progress line for one download.
// nameWidth is the column width for the package name (for alignment across lines).
// width is the terminal column count; the line is sized to fit without wrapping.
// Does NOT include \r, \033[K, or \n — caller controls line management.
func renderLine(s *DownloadState, nameWidth, width int) string {
	if width < 40 {
		width = 40
	}

	name := s.Name
	done := atomic.LoadInt64(&s.DoneBytes)
	total := s.TotalBytes
	elapsed := time.Since(s.StartTime)

	var speed float64
	if elapsed.Seconds() > 0.5 {
		speed = float64(done) / elapsed.Seconds()
	}

	var pct float64
	if total > 0 {
		pct = float64(done) / float64(total) * 100
	}

	// Fixed-width columns matching pacman layout
	// Size column shows bytes downloaded so far (like pacman's xfered)
	xferedStr := fmt.Sprintf("%9s", formatSize(done))
	speedStr := fmt.Sprintf("%11s", "---")
	if speed > 0 {
		speedStr = fmt.Sprintf("%11s", fmt.Sprintf("%s/s", formatSize(int64(speed))))
	}

	// ETA (time remaining) — pacman style
	etaStr := "--:--"
	if speed > 0 && total > 0 {
		remaining := float64(total-done) / speed
		if remaining < 0 {
			remaining = 0
		}
		rs := int(remaining)
		etaStr = fmt.Sprintf("%02d:%02d", rs/60, rs%60)
	}

	pctStr := fmt.Sprintf("%4s", fmt.Sprintf("%.0f%%", pct))

	// Truncate or pad name to nameWidth
	if len(name) > nameWidth {
		name = name[:nameWidth]
	}
	namePadded := fmt.Sprintf("%-*s", nameWidth, name)

	prefix := fmt.Sprintf(" %s %s %s %s [", namePadded, xferedStr, speedStr, etaStr)
	suffix := fmt.Sprintf("] %s", pctStr)
	barWidth := width - len(prefix) - len(suffix)
	if barWidth < 5 {
		barWidth = 5
	}

	filled := 0
	if total > 0 {
		filled = int(float64(barWidth) * float64(done) / float64(total))
		if filled > barWidth {
			filled = barWidth
		}
	}
	bar := strings.Repeat("#", filled) + strings.Repeat("-", barWidth-filled)

	return prefix + bar + suffix
}

func formatSize(bytes int64) string {
	if bytes < 0 {
		return "??? MiB"
	}
	const (
		kib = 1024
		mib = kib * 1024
		gib = mib * 1024
	)
	switch {
	case bytes >= gib:
		return fmt.Sprintf("%.1f GiB", float64(bytes)/float64(gib))
	case bytes >= mib:
		return fmt.Sprintf("%.1f MiB", float64(bytes)/float64(mib))
	case bytes >= kib:
		return fmt.Sprintf("%.1f KiB", float64(bytes)/float64(kib))
	default:
		return fmt.Sprintf("%d B", bytes)
	}
}
