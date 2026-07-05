//go:build linux

package firewall

import (
	"os"
	"testing"
)

func TestIsProcessPrivileged_Root(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("requires root to assert privileged")
	}
	if !isProcessPrivileged() {
		t.Fatal("expected privileged when euid is 0")
	}
}

func TestDefaultPrivilegeHint_NonEmpty(t *testing.T) {
	if defaultPrivilegeHint() == "" {
		t.Fatal("expected non-empty privilege hint")
	}
}

func TestFinalizeStatus_SetsPlatform(t *testing.T) {
	s := finalizeStatus(Status{Available: false, Backend: "nftables"})
	if s.Platform != "linux" {
		t.Fatalf("platform=%q want linux", s.Platform)
	}
}
