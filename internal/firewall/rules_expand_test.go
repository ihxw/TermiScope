package firewall

import "testing"

func TestExpandAddRuleRequestsMultiPort(t *testing.T) {
	reqs, err := ExpandAddRuleRequests(AddRuleRequest{
		Action:   "allow",
		Port:     "22,80",
		Protocol: "tcp",
		Source:   "0.0.0.0/0",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(reqs) != 1 {
		t.Fatalf("want 1 combined rule, got %d", len(reqs))
	}
	if reqs[0].Port != "22,80" {
		t.Fatalf("unexpected port field: %q", reqs[0].Port)
	}
}

func TestExpandAddRuleRequestsBothProtocols(t *testing.T) {
	reqs, err := ExpandAddRuleRequests(AddRuleRequest{
		Action:   "allow",
		Port:     "53",
		Protocol: "tcp+udp",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(reqs) != 2 {
		t.Fatalf("want 2 rules, got %d", len(reqs))
	}
}

func TestSourceForRuleAny(t *testing.T) {
	if got := sourceForRule("0.0.0.0/0"); got != "any" {
		t.Fatalf("want any, got %q", got)
	}
}

func TestAppendNFTProtocolPortMatch(t *testing.T) {
	got := appendNFTProtocolPortMatch(nil, "tcp", "")
	if len(got) != 3 || got[0] != "meta" || got[1] != "l4proto" || got[2] != "tcp" {
		t.Fatalf("protocol-only: got %v", got)
	}
	got = appendNFTProtocolPortMatch(nil, "tcp", "443")
	if len(got) != 3 || got[0] != "tcp" || got[1] != "dport" || got[2] != "443" {
		t.Fatalf("protocol+port: got %v", got)
	}
	got = appendNFTProtocolPortMatch(nil, "", "")
	if got != nil {
		t.Fatalf("empty match: got %v", got)
	}
}
