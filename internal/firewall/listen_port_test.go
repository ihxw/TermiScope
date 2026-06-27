package firewall

import (
	"strconv"
	"testing"
)

func TestBaselineAllowPorts_ReturnsSSHPort(t *testing.T) {
	SetListenPort(9443)
	ports := baselineAllowPorts()
	if len(ports) != 1 {
		t.Fatalf("expected exactly 1 baseline port, got %v", ports)
	}
	// SSH port is read from sshd_config; default is "22".
	if n, err := strconv.Atoi(ports[0]); err != nil || n < 1 || n > 65535 {
		t.Fatalf("expected valid port number in baseline, got %q", ports[0])
	}
	// Web UI port should NOT be in baseline.
	for _, p := range ports {
		if p == "9443" {
			t.Fatal("web UI port should not be in baseline allow ports")
		}
	}
}
