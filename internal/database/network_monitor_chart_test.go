package database

import (
	"testing"
	"time"

	"github.com/ihxw/termiscope/internal/models"
)

func TestDownsampleNetworkResults(t *testing.T) {
	now := time.Now()
	results := make([]models.NetworkMonitorResult, 3000)
	for i := range results {
		results[i] = models.NetworkMonitorResult{
			TaskID:    1,
			Latency:   float64(i % 100),
			Success:   true,
			CreatedAt: now.Add(time.Duration(i) * time.Second),
		}
	}
	out := DownsampleNetworkResults(results, ChartDisplayMaxPoints)
	if len(out) > ChartDisplayMaxPoints {
		t.Fatalf("downsampled len %d > max %d", len(out), ChartDisplayMaxPoints)
	}
	if len(out) == 0 {
		t.Fatal("expected non-empty output")
	}
}

func TestParseNetworkStatsRange_8h16h(t *testing.T) {
	for _, r := range []string{"8h", "16h", "7d"} {
		d, err := ParseNetworkStatsRange(r)
		if err != nil {
			t.Fatalf("ParseNetworkStatsRange(%q): %v", r, err)
		}
		if d <= 0 {
			t.Fatalf("zero duration for %q", r)
		}
	}
}
