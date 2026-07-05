package ssh

import "testing"

func TestResolveRemoteShell(t *testing.T) {
	tests := []struct {
		shell       string
		osType      string
		wantCmd     string
		wantDefault bool
	}{
		{"", "", "", true},
		{"default", "", "", true},
		{"powershell", "", "powershell.exe -NoLogo", false},
		{"powershell", "windows", "powershell.exe -NoLogo", false},
		{"powershell", "linux", "pwsh -NoLogo", false},
		{"powershell", "darwin", "pwsh -NoLogo", false},
		{"pwsh", "linux", "pwsh -NoLogo", false},
		{"cmd", "windows", "cmd.exe", false},
		{"bash", "linux", "bash -l", false},
	}
	for _, tt := range tests {
		cmd, def := ResolveRemoteShell(tt.shell, tt.osType)
		if cmd != tt.wantCmd || def != tt.wantDefault {
			t.Fatalf("ResolveRemoteShell(%q, %q) = (%q, %v), want (%q, %v)",
				tt.shell, tt.osType, cmd, def, tt.wantCmd, tt.wantDefault)
		}
	}
}
