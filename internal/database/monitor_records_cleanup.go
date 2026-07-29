package database

import (
	"log"
	"time"

	"gorm.io/gorm"
)

const (
	// MonitorRecordsRetention keeps enough history for 7d traffic charts plus buffer.
	MonitorRecordsRetention   = 8 * 24 * time.Hour
	monitorRecordsBatchDelete = 50000
)

// PruneMonitorRecords deletes monitor_records older than retention in batches.
func PruneMonitorRecords(db *gorm.DB, retention time.Duration) (int64, error) {
	if retention <= 0 {
		retention = MonitorRecordsRetention
	}
	cutoff := time.Now().Add(-retention)
	var total int64

	for {
		result := db.Exec(`
			DELETE FROM monitor_records WHERE rowid IN (
				SELECT rowid FROM monitor_records WHERE created_at < ? LIMIT ?
			)`, cutoff, monitorRecordsBatchDelete)
		if result.Error != nil {
			return total, result.Error
		}
		if result.RowsAffected == 0 {
			break
		}
		total += result.RowsAffected
	}
	return total, nil
}

// RunMonitorRecordsMaintenance prunes stale monitor_records rows.
func RunMonitorRecordsMaintenance(db *gorm.DB) {
	n, err := PruneMonitorRecords(db, MonitorRecordsRetention)
	if err != nil {
		if IsDatabaseCorrupted(err) {
			log.Printf("Monitor records maintenance: DATABASE CORRUPTION during prune: %v", err)
		} else {
			log.Printf("Monitor records maintenance: prune failed: %v", err)
		}
		return
	}
	if n > 0 {
		log.Printf("Monitor records maintenance: pruned %d rows older than %v", n, MonitorRecordsRetention)
	}
}
