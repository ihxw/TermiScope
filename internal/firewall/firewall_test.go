package firewall

import "testing"

func TestValidateAddRule(t *testing.T) {
	tests := []struct {
		name    string
		req     AddRuleRequest
		wantErr bool
	}{
		{
			name: "allow tcp port",
			req:  AddRuleRequest{Action: "allow", Port: "22", Protocol: "tcp"},
		},
		{
			name: "deny with source",
			req:  AddRuleRequest{Action: "deny", Port: "8080", Protocol: "tcp", Source: "10.0.0.0/8"},
		},
		{
			name:    "invalid action",
			req:     AddRuleRequest{Action: "drop", Port: "22"},
			wantErr: true,
		},
		{
			name:    "invalid port",
			req:     AddRuleRequest{Action: "allow", Port: "99999"},
			wantErr: true,
		},
		{
			name:    "invalid source",
			req:     AddRuleRequest{Action: "allow", Source: "not-an-ip"},
			wantErr: true,
		},
		{
			name: "multi port comma",
			req:  AddRuleRequest{Action: "allow", Port: "22,80,443", Protocol: "tcp"},
		},
		{
			name: "tcp and udp",
			req:  AddRuleRequest{Action: "allow", Port: "53", Protocol: "tcp+udp"},
		},
		{
			name: "direction out",
			req:  AddRuleRequest{Action: "allow", Port: "443", Protocol: "tcp", Direction: "out"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateAddRule(tt.req)
			if (err != nil) != tt.wantErr {
				t.Fatalf("ValidateAddRule() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidateAddPortForward(t *testing.T) {
	err := ValidateAddPortForward(AddPortForwardRequest{
		IPVersion:  "ipv4",
		Protocol:   "tcp",
		ListenPort: "8080",
		TargetIP:   "192.168.1.10",
		TargetPort: "80",
	})
	if err != nil {
		t.Fatalf("expected valid port forward, got %v", err)
	}

	err = ValidateAddPortForward(AddPortForwardRequest{
		IPVersion:  "ipv4",
		Protocol:   "tcp",
		ListenPort: "8080",
		TargetIP:   "not-ip",
		TargetPort: "80",
	})
	if err == nil {
		t.Fatal("expected invalid target_ip error")
	}
}
