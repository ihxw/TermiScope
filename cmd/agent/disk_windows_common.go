package main

import (
	"sort"
	"unicode/utf16"
)

type windowsDiskUsage struct {
	mountPoint string
	volumeID   string
	used       uint64
	total      uint64
}

func splitUTF16MultiString(buf []uint16) []string {
	var out []string
	start := 0
	for i, v := range buf {
		if v != 0 {
			continue
		}
		if i == start {
			break
		}
		out = append(out, string(utf16.Decode(buf[start:i])))
		start = i + 1
	}
	return out
}

func buildWindowsDiskMetrics(usages []windowsDiskUsage) ([]DiskData, uint64, uint64) {
	var disks []DiskData
	var totalUsed uint64
	var totalSize uint64
	seenVolumes := make(map[string]struct{})
	seenMounts := make(map[string]struct{})

	for _, usage := range usages {
		if usage.mountPoint == "" || usage.total == 0 {
			continue
		}
		if _, ok := seenMounts[usage.mountPoint]; ok {
			continue
		}
		seenMounts[usage.mountPoint] = struct{}{}

		if usage.volumeID != "" {
			if _, ok := seenVolumes[usage.volumeID]; ok {
				continue
			}
			seenVolumes[usage.volumeID] = struct{}{}
		}

		disks = append(disks, DiskData{
			MountPoint: usage.mountPoint,
			Used:       usage.used,
			Total:      usage.total,
		})
		totalUsed += usage.used
		totalSize += usage.total
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize
}
