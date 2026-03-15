//go:build !windows
// +build !windows

package main

import (
	"syscall"
)

// statfsUsage returns used bytes for mountpoint on Unix-like systems.
func statfsUsage(mountpoint string) (uint64, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(mountpoint, &stat); err != nil {
		return 0, err
	}
	bsize := uint64(stat.Frsize)
	if bsize == 0 {
		bsize = uint64(stat.Bsize)
	}
	total := uint64(stat.Blocks) * bsize
	free := uint64(stat.Bfree) * bsize
	used := total - free
	return used, nil
}
