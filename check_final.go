package main

import (
	"fmt"
	"log"

	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/models"
)

func main() {
	// Use correct database path from config
	db, err := database.InitDB("./data/termiscope.db")
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("=== Network Monitor Status ===")

	var hosts []models.SSHHost
	db.Find(&hosts)
	fmt.Printf("\nHosts: %d\n", len(hosts))
	if len(hosts) > 0 {
		for i, h := range hosts {
			if i < 5 {
				fmt.Printf("  #%d: %s\n", h.ID, h.Name)
			}
		}
		if len(hosts) > 5 {
			fmt.Printf("  ... and %d more\n", len(hosts)-5)
		}
	}

	var taskCount int64
	db.Model(&models.NetworkMonitorTask{}).Count(&taskCount)
	fmt.Printf("\nTasks: %d\n", taskCount)
	if taskCount > 0 {
		var tasks []models.NetworkMonitorTask
		db.Find(&tasks)
		for _, t := range tasks {
			fmt.Printf("  #%d: Host=%d %s->%s:%d\n", t.ID, t.HostID, t.Type, t.Target, t.Port)
		}
	}

	var resultCount int64
	db.Model(&models.NetworkMonitorResult{}).Count(&resultCount)
	fmt.Printf("\nResults: %d\n", resultCount)
	if resultCount > 0 {
		var latest models.NetworkMonitorResult
		db.Order("created_at desc").First(&latest)
		fmt.Printf("  Latest: Task#%d %.2fms at %s\n",
			latest.TaskID, latest.Latency, latest.CreatedAt.Format("15:04:05"))
	}

	fmt.Println("\n=== Summary ===")
	if len(hosts) == 0 {
		fmt.Println("❌ No hosts configured")
	} else if taskCount == 0 {
		fmt.Println("⚠️  Hosts exist but no network monitor tasks")
		fmt.Println("   → Need to deploy template from System Management")
	} else if resultCount == 0 {
		fmt.Println("⚠️  Tasks exist but no results yet")
		fmt.Println("   → Check if agent is deployed and running")
	} else {
		fmt.Println("✅ Data is flowing")
	}
}
