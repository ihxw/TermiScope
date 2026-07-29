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
		&models.PasswordResetToken{},
		&models.SecurityEvent{},
		&models.SftpAuditLog{},
		&models.SftpPathBookmark{},
	)
	if err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}

	// Ensure network monitor tables exist (covers upgrades from older builds).
	if err := EnsureNetworkMonitorTables(db); err != nil {
		return fmt.Errorf("failed to migrate network monitor tables: %w", err)
	}

	// Add indexes for performance optimization.
	type indexMigration struct {
		name string
		sql  string
	}
	indexStatements := []indexMigration{
		{"idx_connection_logs_user_id", "CREATE INDEX IF NOT EXISTS idx_connection_logs_user_id ON connection_logs(user_id)"},
		{"idx_connection_logs_connected_at", "CREATE INDEX IF NOT EXISTS idx_connection_logs_connected_at ON connection_logs(connected_at)"},
		{"idx_monitor_records_host_created", "CREATE INDEX IF NOT EXISTS idx_monitor_records_host_created ON monitor_records(host_id, created_at)"},
		{"idx_ssh_hosts_monitor_secret", "CREATE INDEX IF NOT EXISTS idx_ssh_hosts_monitor_secret ON ssh_hosts(monitor_secret)"},
		{"idx_traffic_reset_host_date_status", "CREATE INDEX IF NOT EXISTS idx_traffic_reset_host_date_status ON monitor_traffic_reset_logs(host_id, reset_date, status)"},
		{"idx_sftp_path_bookmarks_lookup", "CREATE INDEX IF NOT EXISTS idx_sftp_path_bookmarks_lookup ON sftp_path_bookmarks(user_id, host_id, type, position)"},
	}
	if db.Migrator().HasTable(&models.NetworkMonitorResult{}) {
		indexStatements = append(indexStatements,
			indexMigration{"idx_network_monitor_results_created_at", "CREATE INDEX IF NOT EXISTS idx_network_monitor_results_created_at ON network_monitor_results(created_at)"},
			indexMigration{"idx_network_monitor_results_task_created", "CREATE INDEX IF NOT EXISTS idx_network_monitor_results_task_created ON network_monitor_results(task_id, created_at)"},
		)
	}
	for _, index := range indexStatements {
		if err := db.Exec(index.sql).Error; err != nil {
			return fmt.Errorf("failed to create index %s: %w", index.name, err)
		}
	}

	// Prune on startup is triggered from cmd/server/main.go (needs encryption key for alerts).

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
