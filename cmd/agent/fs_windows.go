//go:build windows

package main

// getDiskID returns the underlying device ID for a path. Not applicable on Windows.
func getDiskID(path string) uint64 {
	return 0
}

// getPhysicalDevice is a no-op on Windows as physical disk mapping is not needed.
func getPhysicalDevice(devicePath string) string {
	// On Windows, return the device path as-is since physical disk mapping
	// is handled differently and not required for our use case
	return devicePath
}
