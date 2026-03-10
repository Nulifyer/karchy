//go:build windows

package platform

import (
	"fmt"

	"github.com/go-ole/go-ole"
	"github.com/go-ole/go-ole/oleutil"
)

// ShortcutOptions configures a .lnk shortcut file.
type ShortcutOptions struct {
	LnkPath     string // Full path to the .lnk file
	TargetPath  string // Executable to launch
	Arguments   string // Command-line arguments (optional)
	WorkingDir  string // Working directory (optional)
	Description string // Shortcut description (optional)
	IconPath    string // Icon location (optional)
}

// CreateShortcut creates a Windows .lnk shortcut using WScript.Shell COM.
func CreateShortcut(opts ShortcutOptions) error {
	if err := ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		return fmt.Errorf("CoInitialize: %w", err)
	}
	defer ole.CoUninitialize()

	unknown, err := oleutil.CreateObject("WScript.Shell")
	if err != nil {
		return fmt.Errorf("create WScript.Shell: %w", err)
	}
	wsh, err := unknown.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return fmt.Errorf("query IDispatch: %w", err)
	}
	defer wsh.Release()

	cs, err := oleutil.CallMethod(wsh, "CreateShortcut", opts.LnkPath)
	if err != nil {
		return fmt.Errorf("CreateShortcut: %w", err)
	}
	shortcut := cs.ToIDispatch()
	defer shortcut.Release()

	oleutil.PutProperty(shortcut, "TargetPath", opts.TargetPath)
	if opts.Arguments != "" {
		oleutil.PutProperty(shortcut, "Arguments", opts.Arguments)
	}
	if opts.WorkingDir != "" {
		oleutil.PutProperty(shortcut, "WorkingDirectory", opts.WorkingDir)
	}
	if opts.Description != "" {
		oleutil.PutProperty(shortcut, "Description", opts.Description)
	}
	if opts.IconPath != "" {
		oleutil.PutProperty(shortcut, "IconLocation", opts.IconPath)
	}

	if _, err := oleutil.CallMethod(shortcut, "Save"); err != nil {
		return fmt.Errorf("save shortcut: %w", err)
	}
	return nil
}

// ReadShortcutDescription reads the Description field from a .lnk file.
func ReadShortcutDescription(lnkPath string) (string, error) {
	if err := ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		return "", fmt.Errorf("CoInitialize: %w", err)
	}
	defer ole.CoUninitialize()

	unknown, err := oleutil.CreateObject("WScript.Shell")
	if err != nil {
		return "", err
	}
	wsh, err := unknown.QueryInterface(ole.IID_IDispatch)
	if err != nil {
		return "", err
	}
	defer wsh.Release()

	cs, err := oleutil.CallMethod(wsh, "CreateShortcut", lnkPath)
	if err != nil {
		return "", err
	}
	shortcut := cs.ToIDispatch()
	defer shortcut.Release()

	desc, err := oleutil.GetProperty(shortcut, "Description")
	if err != nil {
		return "", err
	}
	return desc.ToString(), nil
}
