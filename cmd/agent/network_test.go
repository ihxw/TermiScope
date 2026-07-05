package main

import (
	"testing"
	"time"
)

func TestDurationMillisecondsPreservesFractionalMilliseconds(t *testing.T) {
	got := durationMilliseconds(1500 * time.Microsecond)
	if got != 1.5 {
		t.Fatalf("durationMilliseconds = %v, want 1.5", got)
	}
}
