package handlers

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestTailLinesReturnsLastLines(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "server.log")
	if err := os.WriteFile(path, []byte("one\ntwo\nthree\nfour\n"), 0644); err != nil {
		t.Fatalf("write log: %v", err)
	}

	got, truncated, err := tailLines(path, 2)
	if err != nil {
		t.Fatalf("tail lines: %v", err)
	}
	want := []string{"three", "four"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	if !truncated {
		t.Fatalf("truncated = false, want true")
	}
}

func TestTailLinesReturnsAllLinesWhenUnderLimit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "error.log")
	if err := os.WriteFile(path, []byte("alpha\nbeta\n"), 0644); err != nil {
		t.Fatalf("write log: %v", err)
	}

	got, truncated, err := tailLines(path, 10)
	if err != nil {
		t.Fatalf("tail lines: %v", err)
	}
	want := []string{"alpha", "beta"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	if truncated {
		t.Fatalf("truncated = true, want false")
	}
}
