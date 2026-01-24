package database

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	// Use pure Go SQLite driver
	_ "modernc.org/sqlite"
)

var DB *gorm.DB

// InitDB initializes the SQLite database connection
func InitDB(dbPath string) (*gorm.DB, error) {
	// Ensure the directory exists
	dir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory: %w", err)
	}

	// Open database connection with pure Go driver (modernc.org/sqlite)
	// Add busy_timeout to handle concurrent access
	// Add _time_format to parse datetime strings automatically
	dsn := dbPath + "?_pragma=busy_timeout(5000)&_time_format=sqlite"
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        dsn,
	}, &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Get underlying SQL database
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get database instance: %w", err)
	}

	// Enable WAL mode for better concurrency
	_, err = sqlDB.Exec("PRAGMA journal_mode=WAL;")
	if err != nil {
		return nil, fmt.Errorf("failed to enable WAL: %w", err)
	}
	_, err = sqlDB.Exec("PRAGMA synchronous=NORMAL;")
	if err != nil {
		return nil, fmt.Errorf("failed to set synchronous mode: %w", err)
	}

	// Set connection pool settings
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(10) // Limit open connections for SQLite

	DB = db
	return db, nil
}

// GetDB returns the database instance
func GetDB() *gorm.DB {
	return DB
}

// CleanupStaleLogs marks orphaned connections as disconnected
func CleanupStaleLogs(db *gorm.DB) error {
	now := time.Now()
	return db.Model(&models.ConnectionLog{}).
		Where("status IN ?", []string{"connecting", "success"}).
		Updates(map[string]interface{}{
			"status":          "disconnected",
			"disconnected_at": &now,
			"error_message":   "terminated by server restart",
		}).Error
}
