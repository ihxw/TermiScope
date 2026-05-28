package database

import (
	"testing"
	"time"

	"github.com/ihxw/termiscope/internal/models"
)

func TestDeriveTrafficRates(t *testing.T) {
	base := time.Now()
	records := []models.MonitorRecord{
		{NetRx: 1000, NetTx: 500, CreatedAt: base},
		{NetRx: 1600, NetTx: 800, CreatedAt: base.Add(time.Minute)},
	}
	pts := deriveTrafficRates(records)
	if len(pts) != 1 {
		t.Fatalf("len=%d want 1", len(pts))
	}
	if pts[0].RxRate != 10 || pts[0].TxRate != 5 {
		t.Fatalf("rates rx=%d tx=%d want 10/5", pts[0].RxRate, pts[0].TxRate)
	}
}

func TestTrafficDeltaRates_counterReset(t *testing.T) {
	rx, tx := trafficDeltaRates(900, 900, 100, 100, 60)
	if rx != 0 || tx != 0 {
		t.Fatalf("expected 0 on counter drop, got %d %d", rx, tx)
	}
}

func TestFetchMonitorRecordsForTraffic_strideSampling(t *testing.T) {
	db := openTestDB(t)
	if err := db.AutoMigrate(&models.MonitorRecord{}); err != nil {
		t.Fatal(err)
	}
	hostID := uint(42)
	base := time.Now().Add(-48 * time.Hour)
	for i := 0; i < maxMonitorRecordsFetch+500; i++ {
		if err := db.Create(&models.MonitorRecord{
			HostID:    hostID,
			NetRx:     uint64(1000 + i*10),
			NetTx:     uint64(500 + i*5),
			CreatedAt: base.Add(time.Duration(i) * time.Minute),
		}).Error; err != nil {
			t.Fatal(err)
		}
	}
	since := base.Add(-time.Minute)
	records, err := fetchMonitorRecordsForTraffic(db, hostID, since)
	if err != nil {
		t.Fatal(err)
	}
	if len(records) > maxMonitorRecordsFetch+200 {
		t.Fatalf("expected SQL sampling to cap rows, got %d", len(records))
	}
	if len(records) < 100 {
		t.Fatalf("expected meaningful sample, got %d", len(records))
	}
}
