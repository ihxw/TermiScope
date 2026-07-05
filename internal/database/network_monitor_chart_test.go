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

func TestRollupNetworkResultsUsesSampleWindows(t *testing.T) {
	now := time.Now()
	results := []models.NetworkMonitorResult{
		{TaskID: 1, Latency: 10, PacketLoss: 0, Success: true, CreatedAt: now},
		{TaskID: 1, Latency: 20, PacketLoss: 0, Success: true, CreatedAt: now.Add(time.Minute)},
		{TaskID: 1, Latency: -1, PacketLoss: 100, Success: false, CreatedAt: now.Add(2 * time.Minute)},
		{TaskID: 1, Latency: 40, PacketLoss: 0, Success: true, CreatedAt: now.Add(3 * time.Minute)},
		{TaskID: 1, Latency: -1, PacketLoss: 100, Success: false, CreatedAt: now.Add(4 * time.Minute)},
	}

	got := RollupNetworkResults(results, 2, 3*time.Minute)
	if len(got) != 3 {
		t.Fatalf("len = %d, want 3", len(got))
	}
	if got[0].Latency != 15 || !got[0].Success {
		t.Fatalf("first rollup = latency %.1f success %v, want 15 true", got[0].Latency, got[0].Success)
	}
	if got[1].Latency != 40 || !got[1].Success {
		t.Fatalf("second rollup = latency %.1f success %v, want 40 true", got[1].Latency, got[1].Success)
	}
	if got[2].Latency != -1 || got[2].Success {
		t.Fatalf("third rollup = latency %.1f success %v, want -1 false", got[2].Latency, got[2].Success)
	}
	if !got[0].CreatedAt.Equal(results[1].CreatedAt) {
		t.Fatalf("first timestamp = %s, want %s", got[0].CreatedAt, results[1].CreatedAt)
	}
}

func TestRollupNetworkResultsDoesNotCrossLargeGaps(t *testing.T) {
	now := time.Now()
	results := []models.NetworkMonitorResult{
		{TaskID: 1, Latency: 10, Success: true, CreatedAt: now},
		{TaskID: 1, Latency: 20, Success: true, CreatedAt: now.Add(30 * time.Minute)},
	}

	got := RollupNetworkResults(results, 2, 3*time.Minute)
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2", len(got))
	}
}

func TestDownsampleNetworkResultsUsesMajoritySuccess(t *testing.T) {
	now := time.Now()
	results := []models.NetworkMonitorResult{
		{TaskID: 1, Latency: -1, PacketLoss: 100, Success: false, CreatedAt: now},
		{TaskID: 1, Latency: 30, PacketLoss: 0, Success: true, CreatedAt: now.Add(time.Minute)},
		{TaskID: 1, Latency: -1, PacketLoss: 100, Success: false, CreatedAt: now.Add(2 * time.Minute)},
	}

	got := DownsampleNetworkResults(results, 1)
	if len(got) != 1 {
		t.Fatalf("len = %d, want 1", len(got))
	}
	if got[0].Success || got[0].Latency != -1 {
		t.Fatalf("downsampled result = latency %.1f success %v, want -1 false", got[0].Latency, got[0].Success)
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
