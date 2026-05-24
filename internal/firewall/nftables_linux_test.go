//go:build linux

package firewall

import (
	"reflect"
	"testing"
)

func TestParseNftPortForwardLineIPv6(t *testing.T) {
	line := `meta nfproto ipv6 ip6 saddr 2001:db8::/64 tcp dport 8443 dnat to [2001:db8::10]:443 comment "web" # handle 9`

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
		"dnat", "to", "127.0.0.1:2201",
		"comment", portForwardOutputComment(rule),
	}
	if !reflect.DeepEqual(got, wantPrefix) {
		t.Fatalf("unexpected args:\n got: %#v\nwant: %#v", got, wantPrefix)
	}
}

func TestIsLoopbackTarget(t *testing.T) {
	if !isLoopbackTarget("127.0.0.1") {
		t.Fatal("expected loopback")
	}
	if isLoopbackTarget("192.168.1.10") {
		t.Fatal("expected non-loopback")
	}
}
