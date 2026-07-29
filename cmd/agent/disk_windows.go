//go:build windows
// +build windows

package main

import (
	"golang.org/x/sys/windows"
)

// collectDiskMetricsWindows collects disk metrics on Windows platform
func collectDiskMetricsWindows() ([]DiskData, uint64, uint64) {
	// Get all logical drives
	var drives [256]uint16
	n, err := windows.GetLogicalDriveStrings(256, &drives[0])
	if err != nil {
		return nil, 0, 0
	}

	driveList := splitUTF16MultiString(drives[:n])
	usages := make([]windowsDiskUsage, 0, len(driveList))
	for _, drive := range driveList {
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

		usages = append(usages, windowsDiskUsage{
			mountPoint: drive,
			volumeID:   getWindowsVolumeID(drive),
			used:       used,
			total:      totalNumberOfBytes,
		})
	}

	disks, totalUsed, totalSize := buildWindowsDiskMetrics(usages)
	if len(disks) == 0 {
		return nil, 0, 0
	}

	return disks, totalUsed, totalSize
}

func getWindowsVolumeID(mountPoint string) string {
	var volumeName [windows.MAX_PATH]uint16
	err := windows.GetVolumeNameForVolumeMountPoint(
		windows.StringToUTF16Ptr(mountPoint),
		&volumeName[0],
		uint32(len(volumeName)),
	)
	if err != nil {
		return ""
	}
	return windows.UTF16ToString(volumeName[:])
}
