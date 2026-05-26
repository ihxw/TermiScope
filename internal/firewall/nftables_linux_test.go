//go:build linux

package firewall

import (
	"reflect"
	"testing"
)

func TestParseNftPortForwardLineIPv6(t *testing.T) {
	line := `meta nfproto ipv6 ip6 saddr 2001:db8::/64 tcp dport 8443 dnat ip6 to [2001:db8::10]:443 comment "web" # handle 9`

	rule := parseNftPortForwardLine(line)
	if rule == nil {
		t.Fatal("expected rule")
	}
	if rule.IPVersion != "ipv6" || rule.Protocol != "tcp" || rule.ListenPort != "8443" {
		t.Fatalf("unexpected listener fields: %+v", rule)
	}
	if rule.Source != "2001:db8::/64" || rule.TargetIP != "2001:db8::10" || rule.TargetPort != "443" {
		t.Fatalf("unexpected target fields: %+v", rule)
	}
	if rule.Comment != "web" {
		t.Fatalf("unexpected comment: %q", rule.Comment)
	}
}

// Verify the parser still accepts the legacy `dnat to ...` syntax produced by older
// TermiScope releases so upgrades don't lose visibility of existing rules.
func TestParseNftPortForwardLineLegacyIPv6(t *testing.T) {
	line := `meta nfproto ipv6 tcp dport 8443 dnat to [2001:db8::10]:443 comment "legacy" # handle 7`
	rule := parseNftPortForwardLine(line)
	if rule == nil {
		t.Fatal("expected legacy rule to parse")
	}
	if rule.IPVersion != "ipv6" || rule.TargetIP != "2001:db8::10" || rule.TargetPort != "443" {
		t.Fatalf("unexpected fields: %+v", rule)
	}
}

func TestBuildPortForwardSupportArgs(t *testing.T) {
	manager := &nftablesManager{}
	rule := PortForwardRule{
		IPVersion:  "ipv4",
		Protocol:   "tcp",
		ListenAddr: "0.0.0.0",
		ListenPort: "8080",
		TargetIP:   "192.168.1.10",
		TargetPort: "80",
		Source:     "10.0.0.0/8",
	}

	got, err := manager.buildPortForwardSupportArgs(rule, "masquerade")
	if err != nil {
		t.Fatal(err)
	}

	want := []string{
		"meta", "nfproto", "ipv4",
		"ct", "status", "dnat",
		"ip", "saddr", "10.0.0.0/8",
		"ip", "daddr", "192.168.1.10",
		"tcp", "dport", "80",
		"masquerade",
		"comment", portForwardSupportComment(rule),
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestBuildPortForwardSupportArgsIPv6(t *testing.T) {
	manager := &nftablesManager{}
	rule := PortForwardRule{
		IPVersion:  "ipv6",
		Protocol:   "tcp",
		ListenAddr: "::",
		ListenPort: "8443",
		TargetIP:   "2001:db8::10",
		TargetPort: "443",
	}
	got, err := manager.buildPortForwardSupportArgs(rule, "accept")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		"meta", "nfproto", "ipv6",
		"ct", "status", "dnat",
		"ip6", "daddr", "2001:db8::10",
		"tcp", "dport", "443",
		"accept",
		"comment", portForwardSupportComment(rule),
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("unexpected args:\n got: %#v\nwant: %#v", got, want)
	}
}

func TestBuildPortForwardArgsIPv4DNATQualifier(t *testing.T) {
	manager := &nftablesManager{}
	req := AddPortForwardRequest{
		IPVersion:  "ipv4",
		Protocol:   "tcp",
		ListenPort: "8080",
		TargetIP:   "192.168.1.10",
		TargetPort: "80",
	}
	args, err := manager.buildPortForwardArgs(req)
	if err != nil {
		t.Fatal(err)
	}
	if !containsSubsequence(args, []string{"dnat", "ip", "to", "192.168.1.10:80"}) {
		t.Fatalf("expected `dnat ip to 192.168.1.10:80`, got %v", args)
	}
}

func TestBuildPortForwardArgsIPv6DNATQualifier(t *testing.T) {
	manager := &nftablesManager{}
	req := AddPortForwardRequest{
		IPVersion:  "ipv6",
		Protocol:   "tcp",
		ListenPort: "8443",
		TargetIP:   "2001:db8::10",
		TargetPort: "443",
	}
	args, err := manager.buildPortForwardArgs(req)
	if err != nil {
		t.Fatal(err)
	}
	if !containsSubsequence(args, []string{"dnat", "ip6", "to", "[2001:db8::10]:443"}) {
		t.Fatalf("expected `dnat ip6 to [2001:db8::10]:443`, got %v", args)
	}
}

func TestBuildPortForwardOutputNATArgs(t *testing.T) {
	manager := &nftablesManager{}
	req := AddPortForwardRequest{
		IPVersion:  "ipv4",
		Protocol:   "tcp",
		ListenPort: "10022",
		TargetIP:   "127.0.0.1",
		TargetPort: "2201",
		Comment:    "docker ssh",
	}

	got, err := manager.buildPortForwardOutputNATArgs(req)
	if err != nil {
		t.Fatal(err)
	}

	rule := portForwardRuleFromRequest(req)
	wantPrefix := []string{
		"meta", "nfproto", "ipv4",
		"tcp", "dport", "10022",
		"dnat", "ip", "to", "127.0.0.1:2201",
		"comment", portForwardOutputComment(rule),
	}
	if !reflect.DeepEqual(got, wantPrefix) {
		t.Fatalf("unexpected args:\n got: %#v\nwant: %#v", got, wantPrefix)
	}
}

func containsSubsequence(haystack, needle []string) bool {
	if len(needle) == 0 {
		return true
	}
	for i := 0; i+len(needle) <= len(haystack); i++ {
		match := true
		for j := range needle {
			if haystack[i+j] != needle[j] {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}

func TestIsLoopbackTarget(t *testing.T) {
	if !isLoopbackTarget("127.0.0.1") {
		t.Fatal("expected loopback")
	}
	if isLoopbackTarget("192.168.1.10") {
		t.Fatal("expected non-loopback")
	}
}
