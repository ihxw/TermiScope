package handlers

import (
	"fmt"
	"os"
	"testing"
)

func TestJoinRemotePathRoot(t *testing.T) {
	if got := joinRemotePath("/", "file.txt"); got != "/file.txt" {
		t.Fatalf("joinRemotePath root: got %q", got)
	}
	if got := joinRemotePath("/tmp/", "../file.txt"); got != "/tmp/file.txt" {
		t.Fatalf("joinRemotePath basename sanitize: got %q", got)
	}
}

func TestRemotePathContains(t *testing.T) {
	cases := []struct {
		parent string
		child  string
		want   bool
	}{
		{"/var/data", "/var/data", true},
		{"/var/data", "/var/data/nested", true},
		{"/var/data", "/var/database", false},
		{"/", "/tmp/file", true},
		{".", "tmp/file", false},
	}

	for _, tc := range cases {
		if got := remotePathContains(tc.parent, tc.child); got != tc.want {
			t.Fatalf("remotePathContains(%q, %q): got %v want %v", tc.parent, tc.child, got, tc.want)
		}
	}
}

func TestIsRemoteNotExistError(t *testing.T) {
	if !isRemoteNotExistError(os.ErrNotExist) {
		t.Fatalf("os.ErrNotExist should be recognized")
	}
	if !isRemoteNotExistError(fmt.Errorf("sftp: no such file")) {
		t.Fatalf("SFTP no such file should be recognized")
	}
	if isRemoteNotExistError(fmt.Errorf("permission denied")) {
		t.Fatalf("permission denied should not be treated as not found")
	}
}
