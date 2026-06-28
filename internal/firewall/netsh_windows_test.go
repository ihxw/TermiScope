//go:build windows

package firewall

import "testing"

func TestNetshTermiScopeRuleName(t *testing.T) {
	got := netshTermiScopeRuleName("allow", "TCP", "443", "Admin UI")
	if got != "TermiScope-allow-tcp-443-Admin_UI" {
		t.Fatalf("unexpected rule name: %q", got)
	}
	if !isTermiScopeNetshRule(got) {
		t.Fatalf("expected managed rule")
	}
}

func TestSanitizeNetshNamePart(t *testing.T) {
	got := sanitizeNetshNamePart(`bad " name`)
	if got != "bad___name" {
		t.Fatalf("unexpected sanitized name: %q", got)
	}
}
