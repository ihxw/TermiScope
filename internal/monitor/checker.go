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
func StartMonitorChecker(db *gorm.DB) {
	ticker := time.NewTicker(10 * time.Second)
	go func() {
		for range ticker.C {
			checkOfflineHosts(db)
		}
	}()
}

func checkOfflineHosts(db *gorm.DB) {
	// Find all ONLINE hosts with monitoring enabled
	var hosts []models.SSHHost
	if err := db.Where("monitor_enabled = ? AND status = ?", true, "online").Find(&hosts).Error; err != nil {
		log.Printf("Monitor Checker: Failed to query hosts: %v", err)
		return
	}

	for _, host := range hosts {
		// Default to 1 minute if 0
		minutes := host.NotifyOfflineThreshold
		if minutes <= 0 {
			minutes = 1
		}

		threshold := time.Now().Add(-time.Duration(minutes) * time.Minute)

		if host.LastPulse.Before(threshold) {
			// Mark as offline
			host.Status = "offline"
			if err := db.Save(&host).Error; err != nil {
				log.Printf("Monitor Checker: Failed to update host %d status: %v", host.ID, err)
				continue
			}

			// Create Log Entry
			logEntry := models.MonitorStatusLog{
				HostID:    host.ID,
				Status:    "offline",
				CreatedAt: time.Now(),
			}
			db.Create(&logEntry)

			log.Printf("Monitor: Host %s (ID: %d) marked offline (Last Pulse: %v)", host.Name, host.ID, host.LastPulse)

			// Send Notification
			if host.NotifyOfflineEnabled {
				utils.SendNotification(db, host,
					fmt.Sprintf("Host Offline Alert: %s", host.Name),
					fmt.Sprintf("Host '%s' (ID: %d) has gone offline.\nLast Pulse: %s", host.Name, host.ID, host.LastPulse.Format("2006-01-02 15:04:05")),
				)
			}
		}
	}
}
