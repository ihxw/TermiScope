//go:build linux

package firewall

import "testing"

func TestParseIPTablesLine(t *testing.T) {
	line := "-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT"
	rule := parseIPTablesLine(line)
	if rule == nil {
		t.Fatal("expected rule")
	}
	if rule.Port != "22" || rule.Protocol != "tcp" || rule.Action != "allow" {
		t.Fatalf("unexpected rule: %+v", rule)
	}
}

func TestParseFirewalldRichRule(t *testing.T) {
	line := `rule family="ipv4" source address="10.0.0.0/8" port port="8080" protocol="tcp" accept`
	rule := parseFirewalldRichRule(line)
	if rule == nil {
		t.Fatal("expected rule")
	}
	if rule.Port != "8080" || rule.Source != "10.0.0.0/8" || rule.Action != "allow" {
		t.Fatalf("unexpected rule: %+v", rule)
	}
}

func TestRuleToAddRequest(t *testing.T) {
	req := ruleToAddRequest(Rule{Action: "deny", Port: "443", Protocol: "tcp", Source: "192.168.1.1"})
	if req.Action != "deny" || req.Port != "443" {
		t.Fatalf("unexpected request: %+v", req)
	}
}

func TestParseNftRuleLine(t *testing.T) {
	line := `tcp dport 22 accept comment "ssh" # handle 5`
	rule := parseNftRuleLine(line)
	if rule == nil {
		t.Fatal("expected rule")
	}
	if rule.Port != "22" || rule.Action != "allow" || rule.Comment != "ssh" {
		t.Fatalf("unexpected rule: %+v", rule)
	}
}
