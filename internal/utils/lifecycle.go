package utils

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// RestartSelf creates and executes a temporary script to restart the application.
// It returns an error if the restart process fails to start.
// The caller should call os.Exit(0) shortly after this function returns to allow the script to proceed.
func RestartSelf() error {
	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get executable path: %w", err)
	}
	exePath, err = filepath.Abs(exePath)
	if err != nil {
		return fmt.Errorf("failed to get absolute path: %w", err)
	}

	dir := filepath.Dir(exePath)

	if runtime.GOOS == "windows" {
		scriptPath := filepath.Join(dir, "restart_termiscope.bat")
		// Script: Wait 2s, Start executable detached, Delete self
		content := fmt.Sprintf(`@echo off
timeout /t 2 >nul
start "" "%s"
del "%%~f0"
`, exePath)

		if err := os.WriteFile(scriptPath, []byte(content), 0755); err != nil {
			return fmt.Errorf("failed to write restart script: %w", err)
		}

		// Execute the script detached
		cmd := exec.Command("cmd", "/C", "start", "", scriptPath)
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("failed to run restart script: %w", err)
		}
	} else {
		scriptPath := filepath.Join(dir, "restart_termiscope.sh")
		// Script: Sleep 2s, Start executable background, Delete self
		content := fmt.Sprintf(`#!/bin/sh
sleep 2
"%s" > /dev/null 2>&1 &
rm "$0"
`, exePath)

		if err := os.WriteFile(scriptPath, []byte(content), 0755); err != nil {
			return fmt.Errorf("failed to write restart script: %w", err)
		}

		// Execute the script detached
		cmd := exec.Command("/bin/sh", scriptPath)
		// Detach logic could be added here via SysProcAttr if needed,
		// but since the script puts the app in bg, it should be fine.
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("failed to run restart script: %w", err)
		}
	}

	return nil
}
