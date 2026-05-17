package database

import (
	"testing"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	_ "modernc.org/sqlite"
)

func openTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        "file::memory:?cache=shared&_pragma=busy_timeout(5000)&_time_format=sqlite",
	}, &gorm.Config{})
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	if err := EnsureNetworkMonitorTables(db); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return db
}

func TestParseNetworkStatsRange(t *testing.T) {
	cases := []struct {
		in   string
		want time.Duration
	}{
		{"", 24 * time.Hour},
		{"24h", 24 * time.Hour},
		{"1h", time.Hour},
		{"1d", 24 * time.Hour},
		{"7d", 7 * 24 * time.Hour},
	}
	for _, tc := range cases {
		got, err := ParseNetworkStatsRange(tc.in)
		if err != nil {
			t.Fatalf("ParseNetworkStatsRange(%q): %v", tc.in, err)
		}
		if got != tc.want {
			t.Fatalf("ParseNetworkStatsRange(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
}

func TestQueryNetworkMonitorResults(t *testing.T) {
	db := openTestDB(t)

	task := models.NetworkMonitorTask{HostID: 1, Type: "ping", Target: "127.0.0.1", Frequency: 60}
	if err := db.Create(&task).Error; err != nil {
		t.Fatalf("create task: %v", err)
	}

	now := time.Now()
	rows := []models.NetworkMonitorResult{
		{TaskID: task.ID, Latency: 12.5, PacketLoss: 0, Success: true, CreatedAt: now.Add(-2 * time.Hour)},
		{TaskID: task.ID, Latency: 20, PacketLoss: 0, Success: true, CreatedAt: now.Add(-30 * time.Minute)},
	}
	if err := db.Create(&rows).Error; err != nil {
		t.Fatalf("create results: %v", err)
	}

	got, err := QueryNetworkMonitorResults(db, task.ID, now.Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("query: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("got %d results, want 2", len(got))
	}

	got, err = QueryNetworkMonitorResults(db, task.ID, now.Add(-1*time.Hour))
	if err != nil {
		t.Fatalf("query recent: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("got %d recent results, want 1", len(got))
	}
}
