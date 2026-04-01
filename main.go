package main

import (
	"fmt"
	"os"

	"github.com/nulifyer/karchy/internal/actions/webapp"
	"github.com/nulifyer/karchy/internal/arger"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/daemon"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/selfupdate"
	"github.com/nulifyer/karchy/internal/theme"
	"github.com/nulifyer/karchy/internal/tui"
)

// Version is set at build time via -ldflags "-X main.Version=v1.2.3"
var Version = "dev"

func main() {
	tui.Version = Version

	arger.RegisterFlag(arger.Flag[bool]{
		Name:        "debug",
		Aliases:     []string{"--debug"},
		Default:     arger.Optional(false),
		Description: "Enable debug logging",
	})

	arger.RegisterFlag(arger.Flag[string]{
		Name:       "command",
		Aliases:    []string{"--command"},
		Positional: true,
		Default:    arger.Optional(""),
	})

	flags, extra := arger.ParseFlags()

	debug := arger.GetFlag[bool](flags, "debug")
	logging.Init(debug)
	defer logging.Close()
	logging.Info("args=%v debug=%v version=%s", os.Args, debug, Version)
	selfupdate.CleanOld()

	command := arger.GetFlag[string](flags, "command")

	switch command {
	case "", "menu":
		tui.Run()
	case "webapp":
		if len(extra) == 0 {
			fmt.Println("Usage: karchy webapp <new|launch|remove>")
			os.Exit(1)
		}
		switch extra[0] {
		case "new":
			webapp.RunNew()
		case "launch":
			if len(extra) < 2 {
				fmt.Println("Usage: karchy webapp launch <url>")
				os.Exit(1)
			}
			webapp.Launch(extra[1])
		case "remove":
			webapp.RunRemove()
		default:
			fmt.Printf("Unknown webapp action: %s\n", extra[0])
			os.Exit(1)
		}
	case "install-run":
		runAndWait(extra)
	case "menuhost":
		daemon.Version = Version
		daemon.RunMenuHost()
	case "daemon":
		if len(extra) == 0 {
			fmt.Println("Usage: karchy daemon <start|stop|restart|status|run>")
			os.Exit(1)
		}
		switch extra[0] {
		case "start":
			daemon.Start()
		case "stop":
			daemon.Stop()
		case "restart":
			daemon.Restart()
		case "status":
			daemon.Status()
		case "run":
			daemon.Version = Version
			daemon.Run()
		default:
			fmt.Printf("Unknown daemon action: %s\n", extra[0])
			os.Exit(1)
		}
	case "install":
		selfInstall()
	case "uninstall":
		selfUninstall()
	case "update":
		if len(extra) > 0 && extra[0] == "self" {
			if selfupdate.Run(Version) {
				// Restart daemon so it runs the new binary
				daemon.Restart()
			}
		} else {
			// fall through to TUI update menu
			tui.Run()
		}
	case "theme":
		if len(extra) == 0 {
			fmt.Println("Usage: karchy theme <set|get|list> [name]")
			os.Exit(1)
		}
		switch extra[0] {
		case "set":
			if len(extra) < 2 {
				fmt.Println("Usage: karchy theme set <name>")
				os.Exit(1)
			}
			name := extra[1]
			if name != "" && name != "inherit" {
				if _, ok := theme.Load(name); !ok {
					fmt.Printf("Unknown theme: %s\n", name)
					os.Exit(1)
				}
			}
			if name == "inherit" {
				name = ""
			}
			if err := config.SaveTheme(name); err != nil {
				fmt.Fprintf(os.Stderr, "Failed to save theme: %v\n", err)
				os.Exit(1)
			}
		case "get":
			cfg := config.Load()
			if cfg.Theme.Name == "" {
				fmt.Println("inherit")
			} else {
				fmt.Println(cfg.Theme.Name)
			}
		case "list":
			for _, name := range theme.List() {
				fmt.Println(name)
			}
		default:
			fmt.Printf("Unknown theme action: %s\n", extra[0])
			os.Exit(1)
		}
	case "version":
		fmt.Println("karchy " + Version)
	default:
		fmt.Printf("Unknown command: %s\n", command)
		os.Exit(1)
	}
}
