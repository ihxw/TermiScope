package utils

import "testing"

func TestParseAgentVersionLdflags(t *testing.T) {
	tests := []struct {
		name    string
		ldflags string
		want    string
		ok      bool
	}{
		{
			name:    "main version with stripped flags",
			ldflags: "-s -w -X main.Version=1.6.18",
			want:    "1.6.18",
			ok:      true,
		},
		{
			name:    "main version with equals form",
			ldflags: "-X=main.Version=v1.6.18",
			want:    "v1.6.18",
			ok:      true,
		},
		{
			name:    "no agent version",
			ldflags: "-s -w -X github.com/ihxw/termiscope/internal/config.Version=1.6.18",
			ok:      false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := ParseAgentVersionLdflags(tt.ldflags)
			if ok != tt.ok {
				t.Fatalf("ok = %v, want %v", ok, tt.ok)
			}
			if got != tt.want {
				t.Fatalf("version = %q, want %q", got, tt.want)
			}
		})
	}
}
