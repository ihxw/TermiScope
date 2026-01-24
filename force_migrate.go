package main

import (
	"log"

	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/models"
)

func main() {
	db, err := database.InitDB("termiscope.db")
	if err != nil {
		log.Fatal(err)
	}

	log.Println("Force migrating NetworkMonitorTask...")
	err = db.AutoMigrate(&models.NetworkMonitorTask{})
	if err != nil {
		log.Fatal("Migration failed:", err)
	}
	log.Println("Migration successful.")
}
