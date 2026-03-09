//go:build windows

package install

import (
	"bufio"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/nulifyer/karchy/internal/logging"
	"golang.org/x/sys/windows"
)

const (
	colorGreen = "\033[32m"
	colorRed   = "\033[31m"
	colorCyan  = "\033[36m"
	colorBold  = "\033[1m"
	colorReset = "\033[0m"
)

// resolvedPkg holds the resolved manifest and selected installer for a package.
type resolvedPkg struct {
	pkg       PackageEntry
	manifest  *InstallerManifest
	installer *InstallerEntry
	err       error
}

// enableVT enables ANSI/VT processing on stdout so escape codes (\r, \033[nA, colors) work.
func enableVT() func() {
	h := windows.Handle(os.Stdout.Fd())
	var mode uint32
	if err := windows.GetConsoleMode(h, &mode); err != nil {
		logging.Info("enableVT: GetConsoleMode failed: %v", err)
		return func() {}
	}
	newMode := mode | windows.ENABLE_VIRTUAL_TERMINAL_PROCESSING | windows.ENABLE_PROCESSED_OUTPUT
	if err := windows.SetConsoleMode(h, newMode); err != nil {
		logging.Info("enableVT: SetConsoleMode failed: %v", err)
		return func() {}
	}
	logging.Info("enableVT: enabled (old=%#x new=%#x)", mode, newMode)
	return func() { windows.SetConsoleMode(h, mode) }
}

// BatchInstall resolves, downloads (parallel with progress), and installs packages sequentially.
func BatchInstall(pkgs []PackageEntry) {
	batchPipeline(pkgs, true)
}

// BatchVerify resolves, downloads, and verifies packages without installing.
func BatchVerify(pkgs []PackageEntry) {
	batchPipeline(pkgs, false)
}

func batchPipeline(pkgs []PackageEntry, doInstall bool) {
	if len(pkgs) == 0 {
		return
	}

	restoreVT := enableVT()
	defer restoreVT()

	logging.Info("batchPipeline: %d packages (install=%v)", len(pkgs), doInstall)

	// Filter out packages that are already up to date
	installed := InstalledIDs()
	var need []PackageEntry
	for _, p := range pkgs {
		if ver, ok := installed[p.ID]; ok && ver != "" {
			latest := ParseSemVer(p.Version)
			current := ParseSemVer(ver)
			if !latest.IsNewerThan(current) {
				continue
			}
		}
		need = append(need, p)
	}
	if len(need) == 0 {
		fmt.Printf("\n %s%s:: Everything is up to date.%s\n\n", colorBold, colorGreen, colorReset)
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return
	}
	pkgs = need

	// List packages like pacman
	fmt.Printf("\n Packages (%d)\n\n", len(pkgs))
	for _, p := range pkgs {
		if ver, ok := installed[p.ID]; ok && ver != "" {
			fmt.Printf(" %s  %s%s%s → %s%s%s\n", p.Name, colorRed, ver, colorReset, colorGreen, p.Version, colorReset)
		} else {
			fmt.Printf(" %s  %s%s%s\n", p.Name, colorGreen, p.Version, colorReset)
		}
	}

	fmt.Printf("\n %s%s:: Proceed with installation? [Y/n]%s ", colorBold, colorCyan, colorReset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	// Phase 1: Resolve manifests
	resolved := phaseResolve(pkgs)
	if len(resolved) == 0 {
		fmt.Printf("\n %s:: No packages could be resolved.%s\n", colorRed, colorReset)
		return
	}

	// Phase 2: Download all in parallel with progress
	paths := phaseDownload(resolved)

	// Clean up all downloaded files when done
	defer func() {
		for _, p := range paths {
			if p != "" {
				os.Remove(p)
			}
		}
	}()

	// Phase 3: Verify hashes
	verified := phaseVerify(resolved, paths)

	if !doInstall {
		// Verify-only: print summary and return
		fmt.Println()
		var pass, fail int
		for i, r := range resolved {
			if verified[i] {
				fmt.Printf(" %s✓ %s v%s — hash OK%s\n", colorGreen, r.pkg.Name, r.manifest.Version, colorReset)
				pass++
			} else {
				fmt.Printf(" %s✗ %s — verification failed%s\n", colorRed, r.pkg.Name, colorReset)
				fail++
			}
		}
		fmt.Printf("\n %d passed, %d failed\n", pass, fail)
		return
	}

	// Phase 4: Install sequentially
	phaseInstall(resolved, paths, verified)

	// Wait for keypress so the user can see results before the window closes
	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}

func phaseResolve(pkgs []PackageEntry) []resolvedPkg {
	fmt.Printf("\n %s%s:: Resolving packages...%s\n", colorBold, colorCyan, colorReset)

	results := make([]resolvedPkg, len(pkgs))
	var wg sync.WaitGroup

	for i, pkg := range pkgs {
		wg.Add(1)
		go func(i int, pkg PackageEntry) {
			defer wg.Done()
			r := resolvedPkg{pkg: pkg}

			manifest, err := FetchManifest(pkg.ID, pkg.Version)
			if err != nil {
				r.err = err
				results[i] = r
				return
			}
			r.manifest = manifest

			entry, err := SelectInstaller(manifest)
			if err != nil {
				r.err = err
				results[i] = r
				return
			}
			r.installer = entry
			results[i] = r
		}(i, pkg)
	}
	wg.Wait()

	// Print results
	var good []resolvedPkg
	for i, r := range results {
		if r.err != nil {
			fmt.Printf(" %s[%d/%d] %s — %sfailed: %v%s\n",
				colorRed, i+1, len(results), r.pkg.Name, colorRed, r.err, colorReset)
		} else {
			fmt.Printf(" [%d/%d] %s v%s — %s %s\n",
				i+1, len(results), r.pkg.Name, r.manifest.Version,
				r.installer.EffectiveType(r.manifest), r.installer.Architecture)
			good = append(good, r)
		}
	}

	return good
}

func termWidth() int {
	var info windows.ConsoleScreenBufferInfo
	h := windows.Handle(os.Stdout.Fd())
	if err := windows.GetConsoleScreenBufferInfo(h, &info); err != nil {
		logging.Info("termWidth: GetConsoleScreenBufferInfo failed: %v (fallback 80)", err)
		return 80
	}
	w := int(info.Window.Right-info.Window.Left) + 1
	logging.Info("termWidth: %d (buf=%d, window L=%d R=%d)", w, info.Size.X, info.Window.Left, info.Window.Right)
	if w < 40 {
		return 80
	}
	return w
}

func phaseDownload(resolved []resolvedPkg) []string {
	fmt.Printf("\n %s%s:: Downloading...%s\n", colorBold, colorCyan, colorReset)

	cols := termWidth()
	states := make([]*DownloadState, len(resolved))
	paths := make([]string, len(resolved))

	maxNameLen := 0
	for i, r := range resolved {
		states[i] = &DownloadState{
			Name:       r.pkg.ID,
			TotalBytes: -1,
		}
		if len(r.pkg.ID) > maxNameLen {
			maxNameLen = len(r.pkg.ID)
		}
	}

	// Hide cursor during progress display
	os.Stdout.WriteString("\033[?25l")

	// Start downloads
	var wg sync.WaitGroup
	sem := make(chan struct{}, 6) // max 6 parallel downloads

	for i, r := range resolved {
		wg.Add(1)
		go func(i int, r resolvedPkg) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			states[i].StartTime = time.Now()
			states[i].Active = true
			path, err := DownloadFile(r.installer.InstallerURL, states[i].Name, states[i])
			if err != nil {
				states[i].Err = err
			}
			states[i].Finished = true
			paths[i] = path
		}(i, r)
	}

	// Render loop: pacman-style multi-line display using CPL (\033[nF)
	// Completed downloads become permanent lines above the managed active area.
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	printed := make([]bool, len(resolved))
	managedLines := 0 // number of active lines currently on screen

	render := func() {
		// Move cursor to top of managed area (active lines from last render)
		if managedLines > 0 {
			fmt.Fprintf(os.Stdout, "\033[%dF", managedLines)
		}

		linesWritten := 0

		// Print newly finished downloads as permanent lines
		for i, s := range states {
			if s.Finished && !printed[i] {
				os.Stdout.WriteString("\033[K" + renderLine(s, maxNameLen, cols) + "\n")
				printed[i] = true
				linesWritten++
			}
		}

		// Print all active downloads
		activeCount := 0
		for _, s := range states {
			if !s.Finished && s.Active {
				os.Stdout.WriteString("\033[K" + renderLine(s, maxNameLen, cols) + "\n")
				linesWritten++
				activeCount++
			}
		}

		// Clear any leftover lines if managed area shrank
		for j := linesWritten; j < managedLines; j++ {
			os.Stdout.WriteString("\033[K\n")
		}

		managedLines = activeCount
	}

	for {
		select {
		case <-ticker.C:
			render()
		case <-done:
			render()
			os.Stdout.WriteString("\033[?25h") // show cursor
			return paths
		}
	}
}

func phaseVerify(resolved []resolvedPkg, paths []string) []bool {
	fmt.Printf("\n %s%s:: Verifying...%s\n", colorBold, colorCyan, colorReset)

	verified := make([]bool, len(resolved))
	for i, r := range resolved {
		if paths[i] == "" {
			fmt.Printf(" [%d/%d] %s — %sskipped (no download)%s\n",
				i+1, len(resolved), r.pkg.Name, colorRed, colorReset)
			continue
		}
		if err := VerifyHash(paths[i], r.installer.SHA256); err != nil {
			logging.Info("BatchInstall: hash failed for %s: %v", r.pkg.Name, err)
			resolved[i].err = err
			fmt.Printf(" [%d/%d] %s — %sfailed%s\n",
				i+1, len(resolved), r.pkg.Name, colorRed, colorReset)
		} else {
			verified[i] = true
			fmt.Printf(" [%d/%d] %s — %sok%s\n",
				i+1, len(resolved), r.pkg.Name, colorGreen, colorReset)
		}
	}
	return verified
}

func phaseInstall(resolved []resolvedPkg, paths []string, verified []bool) {
	fmt.Printf("\n %s%s:: Installing...%s\n", colorBold, colorCyan, colorReset)

	var installed, failed int
	var failures []string

	for i, r := range resolved {
		if !verified[i] {
			fmt.Printf(" [%d/%d] %s — %sskipped (verification failed)%s\n",
				i+1, len(resolved), r.pkg.Name, colorRed, colorReset)
			failed++
			failures = append(failures, fmt.Sprintf("%s: hash verification failed", r.pkg.Name))
			continue
		}

		fmt.Printf(" [%d/%d] Installing %s...", i+1, len(resolved), r.pkg.Name)

		args := SilentArgs(r.manifest, r.installer)
		err := runInstaller(paths[i], r.installer.EffectiveType(r.manifest), args, r.pkg, r.installer.NeedsElevation(r.manifest))
		if err != nil {
			fmt.Printf(" %sfailed%s\n", colorRed, colorReset)
			failed++
			failures = append(failures, fmt.Sprintf("%s: %v", r.pkg.Name, err))
		} else {
			fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
			installed++
		}
	}

	// Summary
	fmt.Println()
	if failed == 0 {
		fmt.Printf(" %s%s:: %d package(s) installed successfully.%s\n\n",
			colorBold, colorGreen, installed, colorReset)
	} else {
		fmt.Printf(" %s%s:: %d installed, %d failed:%s\n",
			colorBold, colorRed, installed, failed, colorReset)
		for _, f := range failures {
			fmt.Printf("    %s- %s%s\n", colorRed, f, colorReset)
		}
		fmt.Println()
	}
}
