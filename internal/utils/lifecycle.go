package utils

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

// RestartSelf creates and executes a temporary script to restart the application,
// then exits the current process so the new binary can take over.
// The restart script waits 2 seconds before launching the new process, giving
// in-flight HTTP responses time to complete before the port is released.
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
		// Script: Sleep 2s, Start executable in background, Delete self
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
		if err := cmd.Start(); err != nil {
			return fmt.Errorf("failed to run restart script: %w", err)
		}
	}

	// Exit the current (old) process so the restart script can launch the new binary.
	// Without this, the old binary keeps running and serving the old version string.
	os.Exit(0)
	return nil // unreachable
}
