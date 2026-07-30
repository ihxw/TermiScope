//go:build !windows
// +build !windows

package main

// collectDiskMetricsWindows is a stub on non-Windows platforms
func collectDiskMetricsWindows() ([]DiskData, uint64, uint64) {
	return nil, 0, 0
}
