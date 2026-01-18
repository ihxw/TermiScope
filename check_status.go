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

	fmt.Println("=== Current Status ===")

	var hosts []models.SSHHost
	db.Find(&hosts)
	fmt.Printf("\nHosts: %d\n", len(hosts))
	if len(hosts) > 0 {
		for _, h := range hosts {
			fmt.Printf("  #%d: %s (%s)\n", h.ID, h.Name, h.Host)
		}
	}

	var taskCount int64
	db.Model(&models.NetworkMonitorTask{}).Count(&taskCount)
	fmt.Printf("\nTasks: %d\n", taskCount)
	if taskCount > 0 {
		var tasks []models.NetworkMonitorTask
		db.Find(&tasks)
		for _, t := range tasks {
			fmt.Printf("  #%d: Host=%d %s -> %s:%d (%ds)\n",
				t.ID, t.HostID, t.Type, t.Target, t.Port, t.Frequency)
		}
	}

	var resultCount int64
	db.Model(&models.NetworkMonitorResult{}).Count(&resultCount)
	fmt.Printf("\nResults: %d\n", resultCount)
	if resultCount > 0 {
		var latest models.NetworkMonitorResult
		db.Order("created_at desc").First(&latest)
		fmt.Printf("  Latest: Task#%d at %s\n", latest.TaskID, latest.CreatedAt.Format("15:04:05"))
	}
}
