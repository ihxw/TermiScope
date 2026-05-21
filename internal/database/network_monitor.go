package database

import (
	"fmt"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// EnsureNetworkMonitorTables creates or updates network monitor tables.
func EnsureNetworkMonitorTables(db *gorm.DB) error {
	if err := db.AutoMigrate(
		&models.NetworkMonitorTask{},
		&models.NetworkMonitorResult{},
		&models.NetworkMonitorTemplate{},
	); err != nil {
		return err
	}

	if !db.Migrator().HasTable(&models.NetworkMonitorResult{}) {
		return fmt.Errorf("network_monitor_results table missing after migration")
	}

	// Backfill NULLs from older schemas so scans into Go types do not fail.
	db.Exec("UPDATE network_monitor_results SET success = 0 WHERE success IS NULL")
	db.Exec("UPDATE network_monitor_results SET packet_loss = 0 WHERE packet_loss IS NULL")
	return nil
}

// ParseNetworkStatsRange parses ?range= values such as 1h, 24h, 1d, 7d.
func ParseNetworkStatsRange(rangeStr string) (time.Duration, error) {
	if rangeStr == "" {
		return 24 * time.Hour, nil
	}
	if len(rangeStr) > 1 && rangeStr[len(rangeStr)-1] == 'd' {
		var days int
		if _, err := fmt.Sscanf(rangeStr[:len(rangeStr)-1], "%d", &days); err == nil && days > 0 {
			return time.Duration(days) * 24 * time.Hour, nil
		}
	}
	return time.ParseDuration(rangeStr)
}

// MaxNetworkMonitorChartPoints caps rows returned for charts (frontend clusters ~10s buckets).
const MaxNetworkMonitorChartPoints = 10000

// MaxNetworkMonitorResultsPerReport limits a single agent upload batch.
const MaxNetworkMonitorResultsPerReport = 500

// QueryNetworkMonitorResults returns results for a task since the given time (newest capped).
func QueryNetworkMonitorResults(db *gorm.DB, taskID uint, since time.Time) ([]models.NetworkMonitorResult, error) {
	results, err := queryNetworkMonitorResults(db, taskID, since)
	if err == nil {
		return results, nil
	}

	// Missing table, stale schema, or legacy NULL rows — repair once and retry.
	if isRepairableQueryError(err) {
		if migrateErr := EnsureNetworkMonitorTables(db); migrateErr != nil {
			return nil, fmt.Errorf("schema repair failed: %w (original: %v)", migrateErr, err)
		}
		return queryNetworkMonitorResults(db, taskID, since)
	}
	return nil, err
}

func queryNetworkMonitorResults(db *gorm.DB, taskID uint, since time.Time) ([]models.NetworkMonitorResult, error) {
	results := make([]models.NetworkMonitorResult, 0)
	err := db.Where("task_id = ? AND created_at > ?", taskID, since.UTC()).
		Order("created_at desc").
		Limit(MaxNetworkMonitorChartPoints).
		Find(&results).Error
	if err != nil {
		return nil, err
	}
	// Return ascending time order for charts.
	for i, j := 0, len(results)-1; i < j; i, j = i+1, j-1 {
		results[i], results[j] = results[j], results[i]
	}
	return results, nil
}

func isRepairableQueryError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "no such table") ||
		strings.Contains(msg, "no such column") ||
		strings.Contains(msg, "has no column") ||
		strings.Contains(msg, "scan error") ||
		strings.Contains(msg, "converting null")
}

// IsDatabaseCorrupted reports SQLite corruption errors that require manual repair.
func IsDatabaseCorrupted(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "database disk image is malformed") ||
		strings.Contains(msg, "file is not a database") ||
		strings.Contains(msg, "database corruption")
}
