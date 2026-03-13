package main

import (
	"fmt"
	"log"

	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/models"
)

func main() {
	db, err := database.InitDB("termiscope.db")
	if err != nil {
		log.Fatal(err)
	}
	var count int64
	db.Model(&models.NetworkMonitorTask{}).Count(&count)
	fmt.Printf("Total Tasks: %d\n", count)

	var tasks []models.NetworkMonitorTask
	db.Find(&tasks)
	for _, t := range tasks {
		fmt.Printf("Task: HostID=%d Type=%s Target=%s Port=%d\n", t.HostID, t.Type, t.Target, t.Port)
	}
}
