package main

import (
	"reflect"
	"testing"
)

func TestSplitUTF16MultiStringParsesWindowsDriveList(t *testing.T) {
	got := splitUTF16MultiString([]uint16{
		'C', ':', '\\', 0,
		'D', ':', '\\', 0,
		0,
	})
	want := []string{`C:\`, `D:\`}

	if !reflect.DeepEqual(got, want) {
		t.Fatalf("splitUTF16MultiString() = %#v, want %#v", got, want)
	}
}

func TestBuildWindowsDiskMetricsDeduplicatesVolumeIDs(t *testing.T) {
	disks, used, total := buildWindowsDiskMetrics([]windowsDiskUsage{
		{mountPoint: `C:\`, volumeID: `\\?\Volume{system}\`, used: 40, total: 100},
		{mountPoint: `C:\Mount\Data\`, volumeID: `\\?\Volume{system}\`, used: 40, total: 100},
		{mountPoint: `D:\`, volumeID: `\\?\Volume{data}\`, used: 10, total: 50},
	})

	wantDisks := []DiskData{
		{MountPoint: `C:\`, Used: 40, Total: 100},
		{MountPoint: `D:\`, Used: 10, Total: 50},
	}
	if !reflect.DeepEqual(disks, wantDisks) {
		t.Fatalf("disks = %#v, want %#v", disks, wantDisks)
	}
	if used != 50 {
		t.Fatalf("used = %d, want 50", used)
	}
	if total != 150 {
		t.Fatalf("total = %d, want 150", total)
	}
}
