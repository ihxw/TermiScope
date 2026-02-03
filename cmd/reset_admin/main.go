package main

import (
	"fmt"
	"log"

	"github.com/ihxw/termiscope/internal/models"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	// Import pure Go SQLite driver
	_ "modernc.org/sqlite"
)

func main() {
	dbPath := "data/termiscope.db"
	fmt.Printf("Opening database at %s (using modernc.org/sqlite)...\n", dbPath)

	// Use pure Go driver settings
	dsn := dbPath + "?_pragma=busy_timeout(5000)&_time_format=sqlite"
	db, err := gorm.Open(sqlite.Dialector{
		DriverName: "sqlite",
		DSN:        dsn,
	}, &gorm.Config{})

	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}

	var user models.User
	if err := db.First(&user, "username = ?", "admin").Error; err != nil {
		log.Fatalf("failed to find admin user: %v", err)
	}

	newPassword := "admin123"
	fmt.Printf("Resetting password for user 'admin'...\n")

	if err := user.SetPassword(newPassword); err != nil {
		log.Fatalf("failed to set password: %v", err)
	}

	if err := db.Save(&user).Error; err != nil {
		log.Fatalf("failed to save user: %v", err)
	}

	fmt.Println("========================================")
	fmt.Printf("SUCCESS: Password for user 'admin' has been reset to: %s\n", newPassword)
	fmt.Println("========================================")
}
