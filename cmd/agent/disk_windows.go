//go:build windows
// +build windows

package main

import (
	"sort"
	"strings"

	"golang.org/x/sys/windows"
)

// collectDiskMetricsWindows collects disk metrics on Windows platform
func collectDiskMetricsWindows() ([]DiskData, uint64, uint64) {
	var disks []DiskData
	var totalUsed uint64
	var totalSize uint64

	// Get all logical drives
	var drives [256]uint16
	n, err := windows.GetLogicalDriveStrings(256, &drives[0])
	if err != nil {
		return nil, 0, 0
	}

	// Convert to Go string and split
	driveBytes := make([]byte, n*2)
	for i := 0; i < int(n); i++ {
		driveBytes[i*2] = byte(drives[i])
		driveBytes[i*2+1] = byte(drives[i] >> 8)
	}
	driveStr := string(driveBytes)
	driveList := strings.Split(driveStr, "\x00")

	for _, drive := range driveList {
		if drive == "" {
			continue
		}

		// Get disk free space
		var freeBytesAvailable, totalNumberOfBytes, totalNumberOfFreeBytes uint64
		err := windows.GetDiskFreeSpaceEx(
			windows.StringToUTF16Ptr(drive),
			&freeBytesAvailable,
			&totalNumberOfBytes,
			&totalNumberOfFreeBytes,
		)
		if err != nil {
			continue
		}

		// Skip if total is 0 (invalid disk)
		if totalNumberOfBytes == 0 {
			continue
		}

		// Calculate used space
		used := totalNumberOfBytes - totalNumberOfFreeBytes

		disks = append(disks, DiskData{
			MountPoint: drive,
			Used:       used,
			Total:      totalNumberOfBytes,
		})
		totalUsed += used
		totalSize += totalNumberOfBytes
	}

	if len(disks) == 0 {
		return nil, 0, 0
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize
}
