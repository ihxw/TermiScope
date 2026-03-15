//go:build windows

package main

// getDiskID returns the underlying device ID for a path. Not applicable on Windows.
func getDiskID(path string) uint64 {
	return 0
}
