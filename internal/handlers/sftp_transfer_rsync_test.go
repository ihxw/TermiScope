package handlers

import (
	"strings"
	"testing"

	"github.com/ihxw/termiscope/internal/models"
)

func TestParseRsyncProgressLine(t *testing.T) {
	tests := []struct {
		line    string
		percent int
		speed   string
		ok      bool
	}{
		{
			line:    "    12,345,678   50%  123.45MB/s    0:00:05 (xfr#10, to-chk=5/15)",
			percent: 50,
			speed:   "123.45MB/s",
			ok:      true,
		},
		{
			line:    "  1,234,567  12%  1.20MB/s    0:00:01 (xfr#1, to-chk=0/1)",
			percent: 12,
			speed:   "1.20MB/s",
			ok:      true,
		},
		{
			line:    "no progress here",
			ok:      false,
		},
	}

	for _, tt := range tests {
		pct, speed, ok := parseRsyncProgressLine(tt.line)
		if ok != tt.ok {
			t.Fatalf("line %q: ok=%v want %v", tt.line, ok, tt.ok)
		}
		if !tt.ok {
			continue
		}
		if pct != tt.percent || speed != tt.speed {
			t.Fatalf("line %q: got %d %q want %d %q", tt.line, pct, speed, tt.percent, tt.speed)
		}
	}
}

func TestRsyncRemoteDest(t *testing.T) {
	got := rsyncRemoteDest("root", "10.0.0.2", "/data/backup", "", true)
	want := "root@10.0.0.2:/data/backup/"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}

	got = rsyncRemoteDest("root", "10.0.0.2", "/data/backup", "copy.txt", false)
	want = "root@10.0.0.2:/data/backup/copy.txt"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestBuildRemoteRsyncInstallScript(t *testing.T) {
	script := buildRemoteRsyncInstallScript()
	for _, needle := range []string{
		"command -v rsync",
		"apt-get install -y rsync",
		"dnf install -y rsync",
		"apk add --no-cache rsync",
		"sudo -n",
	} {
		if !strings.Contains(script, needle) {
			t.Fatalf("install script missing %q:\n%s", needle, script)
		}
	}
}

func TestBuildRsyncCommand(t *testing.T) {
	auth := &directTransferAuth{
		sshForRsync: "ssh -i '/tmp/ts_key_abc' -p 22 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMP_HOSTS",
	}
	dst := models.SSHHost{Username: "root", Host: "10.0.0.2", Port: 22}
	cmd := buildRsyncCommand(auth, dst, "/var/log/app.log", "/backup", "", false)
	if !strings.Contains(cmd, "rsync -a --info=progress2") {
		t.Fatalf("missing rsync flags: %s", cmd)
	}
	if !strings.Contains(cmd, "/var/log/app.log") {
		t.Fatalf("missing source: %s", cmd)
	}
	if !strings.Contains(cmd, "root@10.0.0.2:/backup/") {
		t.Fatalf("missing dest: %s", cmd)
	}
}

func TestExtractPath(t *testing.T) {
	tests := []struct {
		output   string
		prefix   string
		expected string
	}{
		{
			output:   "/tmp/ts_key_abcdef\n",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_abcdef",
		},
		{
			output:   "mktemp: /tmp/ts_key_123456\nSome error occurred",
			prefix:   "/tmp/ts_key_",
			expected: "/tmp/ts_key_123456",
		},
		{
			output:   "Some error without path",
			prefix:   "/tmp/ts_key_",
			expected: "",
		},
	}

	for _, tt := range tests {
		got := extractPath(tt.output, tt.prefix)
		if got != tt.expected {
			t.Errorf("extractPath(%q, %q) = %q; want %q", tt.output, tt.prefix, got, tt.expected)
		}
	}
}

func TestBuildHostKeyVerifyScript(t *testing.T) {
	dst := models.SSHHost{
		Host:        "10.0.0.1",
		Port:        2222,
		Fingerprint: "SHA256:abc",
	}
	script := buildHostKeyVerifyScript(dst, "/tmp/ts_hosts_xyz", "rm -f /tmp/ts_key_xyz")
	if !strings.Contains(script, "/tmp/ts_hosts_xyz") {
		t.Errorf("script does not contain host path: %s", script)
	}
	if !strings.Contains(script, "SHA256:abc") {
		t.Errorf("script does not contain expected fingerprint: %s", script)
	}
}
