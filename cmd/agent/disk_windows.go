//go:build windows
// +build windows

package main

import (
	"golang.org/x/sys/windows"
)

// statfsUsage returns used bytes for mountpoint on Windows.
func statfsUsage(mountpoint string) (uint64, error) {
	var freeBytesAvailable uint64
	var totalBytes uint64
	var totalFreeBytes uint64

	// Convert mountpoint to UTF-16 for Windows API
	mountPointPtr, err := windows.UTF16PtrFromString(mountpoint)
	if err != nil {
		return 0, err
	}

	// Call Windows API to get disk free space
	err = windows.GetDiskFreeSpaceEx(
		mountPointPtr,
		&freeBytesAvailable,
		&totalBytes,
		&totalFreeBytes,
	)
	if err != nil {
		return 0, err
	}

	// Calculate used bytes
	used := totalBytes - totalFreeBytes
	return used, nil
}
