package utils

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveScriptsFileDevTree(t *testing.T) {
	if _, err := os.Stat("scripts"); err != nil {
		t.Skip("not in repo root")
	}
	p, err := ResolveScriptsFile("orphan_agent_cleanup.sh")
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Base(p) != "orphan_agent_cleanup.sh" {
		t.Fatalf("unexpected path %q", p)
	}
}
