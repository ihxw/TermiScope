//go:build !windows

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"syscall"
)

// getDiskID returns the underlying device ID for a Unix path to help deduplicate identical mounts.
func getDiskID(path string) uint64 {
	info, err := os.Stat(path)
	if err == nil {
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			return uint64(stat.Dev)
		}
	}
	return 0
}

// getPhysicalDevice attempts to derive the underlying physical block device
// for a given device path (e.g. /dev/sda1 -> /dev/sda, /dev/nvme0n1p1 -> /dev/nvme0n1).
// If it cannot determine a parent device, it returns the resolved device path.
func getPhysicalDevice(devicePath string) string {
	if devicePath == "" {
		return ""
	}

	// Resolve any symlinks (e.g. /dev/disk/by-uuid/... -> /dev/sda1)
	resolved, err := filepath.EvalSymlinks(devicePath)
	if err == nil && resolved != "" {
		devicePath = resolved
	}

	base := filepath.Base(devicePath)

	// Strip common partition suffixes: digits or 'p' + digits (nvme)
	re := regexp.MustCompile(`^(.*?)(p?\d+)$`)
	if matches := re.FindStringSubmatch(base); len(matches) == 3 {
		phys := matches[1]
		// Return full path to physical device
		return filepath.Join(filepath.Dir(devicePath), phys)
	}

	return devicePath
}
