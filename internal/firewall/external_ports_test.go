package firewall

import "testing"

func TestMergeEnableAllowWithBaseline(t *testing.T) {
	SetListenPort(9443)

	merged := mergeEnableAllowWithBaseline([]EnableAllowPort{
		{Port: "9443", Protocol: "tcp"},
		{Port: "8080", Protocol: ""},
	})

	seen := map[string]bool{}
	for _, item := range merged {
		seen[item.Protocol+"/"+item.Port] = true
	}
	for _, want := range []string{"tcp/22", "tcp/9443", "tcp/8080"} {
		if !seen[want] {
			t.Fatalf("missing %s in %v", want, merged)
		}
	}
}
