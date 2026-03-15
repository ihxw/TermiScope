package database

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// generateRandomPassword generates a cryptographically secure random password
func generateRandomPassword(length int) (string, error) {
	bytes := make([]byte, length)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	// Use base64 URL encoding for a mix of letters, numbers, and symbols
	password := base64.URLEncoding.EncodeToString(bytes)
	// Trim to desired length
	if len(password) > length {
		password = password[:length]
	}
	return password, nil
}

// RunMigrations runs all database migrations
func RunMigrations(db *gorm.DB) error {
	log.Println("Running database migrations...")

	// Auto migrate all models
	err := db.AutoMigrate(
		&models.User{},
		&models.SSHHost{},
		&models.AgentCommand{},
		&models.ConnectionLog{},
		&models.SystemConfig{},
		&models.CommandTemplate{},
		&models.TerminalRecording{},
		&models.MonitorRecord{},
		&models.MonitorStatusLog{},
		&models.NetworkMonitorTask{},
		&models.MonitorTrafficResetLog{},
		&models.NetworkMonitorResult{},
		&models.NetworkMonitorTemplate{},
		&models.RevokedToken{},
		&models.LoginHistory{},
	)
	if err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}

	// Add indexes for performance optimization
	db.Exec("CREATE INDEX IF NOT EXISTS idx_connection_logs_user_id ON connection_logs(user_id)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_connection_logs_created_at ON connection_logs(created_at)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_network_monitor_results_created_at ON network_monitor_results(created_at)")

	// Check if system needs initial setup
	var count int64
	db.Model(&models.User{}).Count(&count)
	if count == 0 {
		log.Println("========================================")
		log.Println("    NO USERS FOUND - SETUP REQUIRED")
		log.Println("========================================")
		log.Println("Please open the web interface to create")
		log.Println("your admin account.")
		log.Println("========================================")
	}

	log.Println("Database migrations completed successfully")
	return nil
}
