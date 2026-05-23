package firewall

import "testing"

func TestBaselineAllowPorts_IncludesSSHAndListenPort(t *testing.T) {
	SetListenPort(9443)
	ports := baselineAllowPorts()
	found22, found9443 := false, false
	for _, p := range ports {
		if p == "22" {
			found22 = true
		}
		if p == "9443" {
			found9443 = true
		}
	}
	if !found22 || !found9443 {
		t.Fatalf("expected 22 and 9443 in baseline ports, got %v", ports)
	}
}
