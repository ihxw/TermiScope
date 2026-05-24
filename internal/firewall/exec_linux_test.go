//go:build linux

package firewall

import "testing"

func TestNftCommentValueASCII(t *testing.T) {
	got := nftCommentValue("termiscope-established")
	if got != "termiscope-established" {
		t.Fatalf("want bare ASCII comment, got %q", got)
	}
}

func TestNftCommentValueUnicode(t *testing.T) {
	got := nftCommentValue("出栈")
	if got != `"出栈"` {
		t.Fatalf("want double-quoted unicode comment, got %q", got)
	}
}

func TestNftCommentValueSpace(t *testing.T) {
	got := nftCommentValue("my rule")
	if got != `"my rule"` {
		t.Fatalf("want double-quoted comment, got %q", got)
	}
}
