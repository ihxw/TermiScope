package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	probing "github.com/prometheus-community/pro-bing"
)

type NetworkTask struct {
	ID        uint   `json:"id"`
	Type      string `json:"type"` // ping, tcping
	Target    string `json:"target"`
	Port      int    `json:"port"`
	Frequency int    `json:"frequency"` // Seconds
}

type NetworkResult struct {
	TaskID     uint      `json:"task_id"`
	Latency    float64   `json:"latency"`     // ms
	PacketLoss float64   `json:"packet_loss"` // %
	Success    bool      `json:"success"`
	CreatedAt  time.Time `json:"created_at"`
}

type NetworkMonitor struct {
	tasks      map[uint]NetworkTask
	tasksMu    sync.RWMutex
	client     *http.Client
	stopChan   chan struct{}
	resultsBuf []NetworkResult
	bufMu      sync.Mutex
}

func NewNetworkMonitor(client *http.Client) *NetworkMonitor {
	return &NetworkMonitor{
		tasks:    make(map[uint]NetworkTask),
		client:   client,
		stopChan: make(chan struct{}),
	}
}

func (nm *NetworkMonitor) Start() {
	// Sync Config Loop
	go func() {
		nm.syncConfig() // Initial sync
		ticker := time.NewTicker(2 * time.Minute)
		for {
			select {
			case <-ticker.C:
				nm.syncConfig()
			case <-nm.stopChan:
				return
			}
		}
	}()

	// Execution Loop
	// Since tasks have different frequencies, we can't just use one ticker.
	// We can use a main ticker (e.g. 1s) and check if task needs running?
	// Or launch a goroutine per task?
	// Goroutine per task is easiest for varying frequencies.
	// But we need to manage them when config changes.
	// Simplified approach for now:
	// A new "Runner" routine is spawned for each task ID.
	// We keep track of running tasks.

	// Actually, the requirement says "Default ... 1 min".
	// If most tasks are 1 min, we can batch them.
	// But getting complicated.
	// Let's just run a master loop every 10 seconds?
	// If a task frequency is 60s, it runs every 6th tick?
	// Better: Each task has NextRun time.
}

// Simple Runner:
// We just sync config. For every task in config, if it's new, start a goroutine.
// If it's removed, stop goroutine (need context or channel).
// For simplicity in this iteration:
// SyncConfig updates the map.
// A main loop runs every 1 second.
// It iterates tasks. If time.Now() > task.NextRun, execute.
// But we need to store NextRun state.

// Let's verify how complex this needs to be.
// "Default set client interval 1 min".
// User can set config.
// I'll implement a simple Task Manager.

func (nm *NetworkMonitor) StartSimple() {
	go func() {
		// Sync every minute
		syncTicker := time.NewTicker(1 * time.Minute)
		// Run loop
		runTicker := time.NewTicker(1 * time.Second) // Check every second

		taskState := make(map[uint]time.Time) // Last Run

		for {
			select {
			case <-syncTicker.C:
				nm.syncConfig()

			case <-runTicker.C:
				nm.tasksMu.RLock()
				tasks := make([]NetworkTask, 0, len(nm.tasks))
				for _, t := range nm.tasks {
					tasks = append(tasks, t)
				}
				nm.tasksMu.RUnlock()

				now := time.Now()
				for _, task := range tasks {
					lastRun, exists := taskState[task.ID]
					freq := time.Duration(task.Frequency) * time.Second
					if freq == 0 {
						freq = 60 * time.Second
					}

					if !exists || now.Sub(lastRun) >= freq {
						// Run Task
						taskState[task.ID] = now
						go nm.executeTask(task)
					}
				}
			}
		}
	}()

	// Report Loop
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		for range ticker.C {
			nm.flushResults()
		}
	}()
}

func (nm *NetworkMonitor) syncConfig() {
	// GET /api/monitor/network/tasks
	req, err := http.NewRequest("GET", serverURL+"/api/monitor/network/tasks", nil)
	if err != nil {
		log.Printf("NetMon: Req create failed: %v", err)
		return
	}
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := nm.client.Do(req)
	if err != nil {
		log.Printf("NetMon: Sync failed: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		log.Printf("NetMon: Sync status %d", resp.StatusCode)
		return
	}

	var respData struct {
		Tasks []NetworkTask `json:"tasks"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&respData); err != nil {
		log.Printf("NetMon: Decode failed: %v", err)
		return
	}

	nm.tasksMu.Lock()
	// Replace map? Or merge?
	// Replacing is easiest to handle deletions (old tasks are gone).
	newMap := make(map[uint]NetworkTask)
	for _, t := range respData.Tasks {
		newMap[t.ID] = t
	}
	nm.tasks = newMap
	nm.tasksMu.Unlock()
}

func (nm *NetworkMonitor) executeTask(task NetworkTask) {
	var res NetworkResult
	res.TaskID = task.ID
	res.CreatedAt = time.Now()

	if task.Type == "ping" {
		res.Success, res.Latency, res.PacketLoss = ping(task.Target)
	} else if task.Type == "tcping" {
		res.Success, res.Latency = tcping(task.Target, task.Port)
	}

	nm.bufMu.Lock()
	nm.resultsBuf = append(nm.resultsBuf, res)
	nm.bufMu.Unlock()
}

func (nm *NetworkMonitor) flushResults() {
	nm.bufMu.Lock()
	if len(nm.resultsBuf) == 0 {
		nm.bufMu.Unlock()
		return
	}
	data := nm.resultsBuf
	nm.resultsBuf = make([]NetworkResult, 0) // Clear
	nm.bufMu.Unlock()

	jsonData, _ := json.Marshal(data)
	req, err := http.NewRequest("POST", serverURL+"/api/monitor/network/report", bytes.NewBuffer(jsonData))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := nm.client.Do(req)
	if err == nil {
		resp.Body.Close()
	} else {
		// If failed, maybe put back in buffer?
		// For now simple lossy.
		log.Printf("NetMon: Report failed: %v", err)
	}
}

func ping(target string) (success bool, latency float64, packetLoss float64) {
	pinger, err := probing.NewPinger(target)
	if err != nil {
		return false, 0, 100
	}

	// Windows specific: privileged
	pinger.SetPrivileged(true)
	// Make it fast: 3 packets
	pinger.Count = 3
	pinger.Timeout = 2 * time.Second

	err = pinger.Run() // Blocks
	if err != nil {
		// Log error?
		return false, 0, 100
	}

	stats := pinger.Statistics()
	success = stats.PacketsRecv > 0
	latency = float64(stats.AvgRtt.Milliseconds())
	if stats.AvgRtt.Microseconds() > 0 && latency == 0 {
		latency = float64(stats.AvgRtt.Microseconds()) / 1000.0
	}
	packetLoss = stats.PacketLoss
	return
}

func tcping(target string, port int) (success bool, latency float64) {
	address := net.JoinHostPort(target, fmt.Sprintf("%d", port))
	start := time.Now()
	conn, err := net.DialTimeout("tcp", address, 2*time.Second)
	if err != nil {
		return false, 0
	}
	defer conn.Close()

	latency = float64(time.Since(start).Milliseconds())
	return true, latency
}
