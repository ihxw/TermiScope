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

	// Check tasks
	var taskCount int64
	db.Model(&models.NetworkMonitorTask{}).Count(&taskCount)
	fmt.Printf("Total NetworkMonitorTasks: %d\n", taskCount)

	if taskCount > 0 {
		var tasks []models.NetworkMonitorTask
		db.Find(&tasks)
		for _, t := range tasks {
			fmt.Printf("  Task ID=%d HostID=%d Type=%s Target=%s:%d Frequency=%ds\n",
				t.ID, t.HostID, t.Type, t.Target, t.Port, t.Frequency)
		}
	}

	// Check results
	var resultCount int64
	db.Model(&models.NetworkMonitorResult{}).Count(&resultCount)
	fmt.Printf("\nTotal NetworkMonitorResults: %d\n", resultCount)

	if resultCount > 0 {
		var results []models.NetworkMonitorResult
		db.Order("created_at desc").Limit(5).Find(&results)
		fmt.Println("Latest 5 results:")
		for _, r := range results {
			fmt.Printf("  TaskID=%d Latency=%.2fms Loss=%.1f%% Success=%v Time=%s\n",
				r.TaskID, r.Latency, r.PacketLoss, r.Success, r.CreatedAt.Format("15:04:05"))
		}
	}
}
