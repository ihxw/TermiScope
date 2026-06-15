package handlers

import (
	"os"
	"strings"
	"testing"

	"github.com/ihxw/termiscope/internal/models"
)

func TestServerSCPEndpoints(t *testing.T) {
	src, dst := serverSCPEndpoints("/var/data/a.bin", "/backup", "", false, true)
	if src != "ts-src:/var/data/a.bin" {
		t.Fatalf("src: got %q", src)
	}
	if dst != "ts-dst:/backup/" {
		t.Fatalf("dst: got %q", dst)
	}

	_, dst = serverSCPEndpoints("/var/data/a.bin", "/backup", "renamed.bin", false, true)
	if dst != "ts-dst:/backup/renamed.bin" {
		t.Fatalf("dst rename: got %q", dst)
	}

	_, dst = serverSCPEndpoints("/var/data/a.bin", "/backup/a.bin", "", false, false)
	if dst != "ts-dst:/backup/a.bin" {
		t.Fatalf("dst file: got %q", dst)
	}
}

func TestWriteServerSSHBundleWithKeys(t *testing.T) {
	src := models.SSHHost{Name: "src", Host: "10.0.0.1", Port: 22, Username: "root"}
	dst := models.SSHHost{Name: "dst", Host: "10.0.0.2", Port: 2222, Username: "admin"}
	key := "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----\n"

	bundle, err := writeServerSSHBundle(src, dst, "", key, "", key)
	if err != nil {
		t.Fatal(err)
	}
	defer bundle.cleanup()

	data, err := os.ReadFile(bundle.configPath)
	if err != nil {
		t.Fatal(err)
	}
	cfg := string(data)
	for _, needle := range []string{"Host ts-src", "Host ts-dst", "10.0.0.1", "10.0.0.2", "IdentityFile"} {
		if !strings.Contains(cfg, needle) {
			t.Fatalf("config missing %q:\n%s", needle, cfg)
		}
	}
}
