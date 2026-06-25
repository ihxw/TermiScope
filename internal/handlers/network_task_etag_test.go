package handlers

import (
	"testing"
	"time"

	"github.com/ihxw/termiscope/internal/models"
)

func TestNetworkTasksETag_changesWithTask(t *testing.T) {
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	tasks := []models.NetworkMonitorTask{
		{ID: 1, Type: "ping", Target: "1.1.1.1", UpdatedAt: base},
	}
	e1 := networkTasksETag(9, tasks)
	tasks[0].Target = "8.8.8.8"
	e2 := networkTasksETag(9, tasks)
	if e1 == e2 {
		t.Fatal("etag should change when task changes")
	}
}

func TestNetworkTasksETag_stableForSameSnapshot(t *testing.T) {
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	tasks := []models.NetworkMonitorTask{
		{ID: 1, Type: "ping", Target: "1.1.1.1", UpdatedAt: base},
	}
	if networkTasksETag(3, tasks) != networkTasksETag(3, tasks) {
		t.Fatal("etag should be stable for identical input")
	}
}
