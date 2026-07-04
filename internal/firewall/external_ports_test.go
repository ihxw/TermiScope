package firewall

import "testing"

func TestMergeEnableAllowWithBaseline(t *testing.T) {
	SetListenPort(9443)

	baselinePorts := baselineAllowPorts()
	if len(baselinePorts) == 0 {
		t.Fatal("expected at least one baseline port")
	}

	merged := mergeEnableAllowWithBaseline([]EnableAllowPort{
		{Port: "9443", Protocol: "tcp"},
		{Port: "8080", Protocol: ""},
	})

	seen := map[string]bool{}
	for _, item := range merged {
		seen[item.Protocol+"/"+item.Port] = true
	}
	wants := []string{"tcp/9443", "tcp/8080"}
	for _, port := range baselinePorts {
		wants = append(wants, "tcp/"+port)
	}
	for _, want := range wants {
		if !seen[want] {
			t.Fatalf("missing %s in %v", want, merged)
		}
	}
}
