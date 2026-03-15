//go:build !windows

package main

import (
	"os"
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
