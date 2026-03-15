//go:build windows
// +build windows

package main

// On Windows, statfs is not available; provide a stub that returns error.
import "errors"

func statfsUsage(mountpoint string) (uint64, error) {
	return 0, errors.New("statfs not supported on windows")
}
