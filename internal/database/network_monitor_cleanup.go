package database

import (
	"fmt"
	"log"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

const (
	networkMonitorRetention       = 24 * time.Hour
	networkMonitorBatchDelete     = 50000
	networkMonitorVacuumMinDel    = 10000 // reclaim file space after large prune
	NetworkMonitorAlertThreshold  = 500000
	networkMonitorAlertCooldown   = 24 * time.Hour
	systemConfigKeyMonitorAlertAt = "network_monitor_alert_sent_at"
)

// PruneNetworkMonitorResults deletes rows older than retention in batches.
// Returns total rows deleted. Batch deletes avoid long locks and huge WAL growth.
func PruneNetworkMonitorResults(db *gorm.DB, retention time.Duration) (int64, error) {
	if retention <= 0 {
		retention = networkMonitorRetention
	}
	cutoff := time.Now().Add(-retention)
	var total int64

	for {
		// SQLite-friendly batched delete (GORM Limit+Delete is unreliable on some drivers).
		result := db.Exec(`
			DELETE FROM network_monitor_results WHERE rowid IN (
				SELECT rowid FROM network_monitor_results WHERE created_at < ? LIMIT ?
			)`, cutoff, networkMonitorBatchDelete)
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

// CountNetworkMonitorResults returns total rows in network_monitor_results.
func CountNetworkMonitorResults(db *gorm.DB) (int64, error) {
	if !db.Migrator().HasTable(&models.NetworkMonitorResult{}) {
		return 0, nil
	}
	var count int64
	err := db.Model(&models.NetworkMonitorResult{}).Count(&count).Error
	return count, err
}

// CheckAndNotifyNetworkMonitorOverflow sends system alerts when row count exceeds threshold (cooldown 24h).
func CheckAndNotifyNetworkMonitorOverflow(db *gorm.DB, encryptionKey string) {
	count, err := CountNetworkMonitorResults(db)
	if err != nil {
		log.Printf("Network monitor alert: count failed: %v", err)
		return
	}
	if count < NetworkMonitorAlertThreshold {
		return
	}

	var cfg models.SystemConfig
	err = db.Where("config_key = ?", systemConfigKeyMonitorAlertAt).First(&cfg).Error
	if err == nil && cfg.ConfigValue != "" {
		if last, parseErr := time.Parse(time.RFC3339, cfg.ConfigValue); parseErr == nil {
			if time.Since(last) < networkMonitorAlertCooldown {
				return
			}
		}
	}

	subject := "Network monitor data volume alert"
	message := fmt.Sprintf(
		"network_monitor_results has %d rows (threshold %d). Automatic retention is 24 hours. "+
			"Use System Settings → Database maintenance to prune, or run scripts/repair_database.sh if the database is corrupt.",
		count, NetworkMonitorAlertThreshold,
	)
	utils.SendSystemAlert(db, encryptionKey, subject, message)

	now := time.Now().UTC().Format(time.RFC3339)
	if cfg.ID == 0 {
		_ = db.Create(&models.SystemConfig{ConfigKey: systemConfigKeyMonitorAlertAt, ConfigValue: now}).Error
	} else {
		_ = db.Model(&cfg).Update("config_value", now).Error
	}
	log.Printf("Network monitor alert: notified admins (%d rows >= %d)", count, NetworkMonitorAlertThreshold)
}

// RunNetworkMonitorMaintenance prunes stale rows and logs when anything was removed.
func RunNetworkMonitorMaintenance(db *gorm.DB, encryptionKey string) {
	CheckAndNotifyNetworkMonitorOverflow(db, encryptionKey)

	n, err := PruneNetworkMonitorResults(db, networkMonitorRetention)
	if err != nil {
		if IsDatabaseCorrupted(err) {
			log.Printf("Network monitor maintenance: DATABASE CORRUPTION during prune: %v — run scripts/repair_database.sh", err)
		} else {
			log.Printf("Network monitor maintenance: prune failed: %v", err)
		}
		return
	}
	if n > 0 {
		log.Printf("Network monitor maintenance: pruned %d rows older than 24h", n)
	}
	if n >= networkMonitorVacuumMinDel {
		log.Println("Network monitor maintenance: large prune complete, running VACUUM to shrink DB file...")
		if err := db.Exec("VACUUM").Error; err != nil {
			log.Printf("Network monitor maintenance: VACUUM failed: %v", err)
		}
	}

	// Re-check after prune; clear alert pressure if below threshold
	if remaining, err := CountNetworkMonitorResults(db); err == nil && remaining < NetworkMonitorAlertThreshold/2 {
		_ = db.Where("config_key = ?", systemConfigKeyMonitorAlertAt).Delete(&models.SystemConfig{}).Error
	}
}
