//go:build linux

package firewall

import (
	"io/fs"
	"testing"
	"testing/fstest"
)

func TestLibvirtBridgeNamesFromEntries(t *testing.T) {
	dir := fstest.MapFS{
		"virbr0":      {Mode: fs.ModeDir | 0755},
		"virbr1":      {Mode: fs.ModeDir | 0755},
		"virbr-test":  {Mode: fs.ModeDir | 0755},
		"docker0":     {Mode: fs.ModeDir | 0755},
		"br0":         {Mode: fs.ModeDir | 0755},
		"vnet0":       {Mode: fs.ModeDir | 0755},
		"virbr10/sub": {Mode: fs.ModeDir | 0755},
	}

	entries, err := fs.ReadDir(dir, ".")
	if err != nil {
		t.Fatalf("ReadDir() error: %v", err)
	}

	got := libvirtBridgeNamesFromEntries(entries)
	want := []string{"virbr-test", "virbr0", "virbr1", "virbr10"}
	if len(got) != len(want) {
		t.Fatalf("unexpected bridge count: got %v want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected bridge[%d]: got %q want %q (all: %v)", i, got[i], want[i], got)
		}
	}
}

func TestLibvirtBridgeNamesFromEntriesNoMatch(t *testing.T) {
	dir := fstest.MapFS{
		"eth0":    {Mode: fs.ModeDir | 0755},
		"docker0": {Mode: fs.ModeDir | 0755},
	}

	entries, err := fs.ReadDir(dir, ".")
	if err != nil {
		t.Fatalf("ReadDir() error: %v", err)
	}

	got := libvirtBridgeNamesFromEntries(entries)
	if len(got) != 0 {
		t.Fatalf("expected no bridges, got %v", got)
	}
}
