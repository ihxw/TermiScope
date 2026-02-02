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
		&models.ConnectionLog{},
		&models.SystemConfig{},
		&models.CommandTemplate{},
		&models.TerminalRecording{},
		&models.MonitorRecord{},
		&models.MonitorStatusLog{},
		&models.NetworkMonitorTask{},
		&models.NetworkMonitorTask{},
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

	// Create default admin user if no users exist
	var count int64
	db.Model(&models.User{}).Count(&count)
	if count == 0 {
		log.Println("Creating default admin user...")

		// Generate random password
		randomPassword, err := generateRandomPassword(16)
		if err != nil {
			return fmt.Errorf("failed to generate random password: %w", err)
		}

		adminUser := &models.User{
			Username:    "admin",
			Email:       "admin@localhost",
			DisplayName: "Administrator",
			Role:        "admin",
			Status:      "active",
		}

		// Set random password
		if err := adminUser.SetPassword(randomPassword); err != nil {
			return fmt.Errorf("failed to set admin password: %w", err)
		}

		if err := db.Create(adminUser).Error; err != nil {
			return fmt.Errorf("failed to create admin user: %w", err)
		}

		// Display password in terminal with prominent formatting
		log.Println("========================================")
		log.Println("    DEFAULT ADMIN USER CREATED")
		log.Println("========================================")
		log.Printf("Username: admin")
		log.Printf("Password: %s", randomPassword)
		log.Println("========================================")
		log.Println("IMPORTANT: Please save this password!")
		log.Println("Change it after first login for security.")
		log.Println("========================================")
	}

	log.Println("Database migrations completed successfully")
	return nil
}
