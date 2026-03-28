package monitor

import (
	"fmt"
	"log"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// StartMonitorChecker starts a background goroutine to check for offline hosts
func StartMonitorChecker(db *gorm.DB, encryptionKey string) {
	ticker := time.NewTicker(10 * time.Second)
	go func() {
		for range ticker.C {
			checkOfflineHosts(db, encryptionKey)
		}
	}()
}

func checkOfflineHosts(db *gorm.DB, encryptionKey string) {
	now := time.Now()

	// === Phase 1: Mark online hosts as offline (NO notification yet) ===
	var onlineHosts []models.SSHHost
	if err := db.Where("monitor_enabled = ? AND status = ?", true, "online").Find(&onlineHosts).Error; err != nil {
		log.Printf("Monitor Checker: Failed to query online hosts: %v", err)
		return
	}

	for _, host := range onlineHosts {
		minutes := host.NotifyOfflineThreshold
		if minutes <= 0 {
			minutes = 1
		}

		threshold := now.Add(-time.Duration(minutes) * time.Minute)

		if host.LastPulse.Before(threshold) {
			// Mark as offline, record OfflineAt, but do NOT send notification yet
			host.Status = "offline"
			host.OfflineAt = &now
			host.OfflineNotified = false
			if err := db.Save(&host).Error; err != nil {
				log.Printf("Monitor Checker: Failed to update host %d status: %v", host.ID, err)
				continue
			}

			// Create Log Entry
			logEntry := models.MonitorStatusLog{
				HostID:    host.ID,
				Status:    "offline",
				CreatedAt: now,
			}
			db.Create(&logEntry)

			log.Printf("Monitor: Host %s (ID: %d) marked offline (Last Pulse: %v), notification deferred", host.Name, host.ID, host.LastPulse)
		}
	}

	// === Phase 2: Send deferred offline notifications ===
	// Find hosts that are offline, have been offline for > 1 minute, and haven't been notified yet
	var pendingHosts []models.SSHHost
	if err := db.Where("monitor_enabled = ? AND status = ? AND offline_notified = ? AND offline_at IS NOT NULL AND offline_at < ?",
		true, "offline", false, now.Add(-1*time.Minute)).Find(&pendingHosts).Error; err != nil {
		log.Printf("Monitor Checker: Failed to query pending offline hosts: %v", err)
		return
	}

	for _, host := range pendingHosts {
		host.OfflineNotified = true
		db.Model(&host).Update("offline_notified", true)

		log.Printf("Monitor: Host %s (ID: %d) confirmed offline, sending notification", host.Name, host.ID)

		if host.NotifyOfflineEnabled {
			utils.SendNotification(db, host,
				fmt.Sprintf("Host Offline Alert: %s", host.Name),
				fmt.Sprintf("Host '%s' (ID: %d) has gone offline.\nLast Pulse: %s", host.Name, host.ID, host.LastPulse.Format("2006-01-02 15:04:05")),
				encryptionKey,
			)
		}
	}
}
