package handlers

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/monitor"
	"github.com/ihxw/termiscope/internal/utils"
	"golang.org/x/crypto/ssh"
	"gorm.io/gorm"
)

type MonitorHandler struct {
	DB         *gorm.DB
	Config     *config.Config
	lastDbSave map[uint]time.Time
	saveMu     sync.Mutex
}

func NewMonitorHandler(db *gorm.DB, cfg *config.Config) *MonitorHandler {
	// Start the hub
	go monitor.GlobalHub.Run()
	// Start Cleanup Routine
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		for range ticker.C {
			// Retention: 24 Hours
			if err := db.Where("created_at < ?", time.Now().Add(-24*time.Hour)).Delete(&models.NetworkMonitorResult{}).Error; err != nil {
				log.Printf("Network Monitor Cleanup Failed: %v", err)
			}
		}
	}()

	return &MonitorHandler{
		DB:         db,
		Config:     cfg,
		lastDbSave: make(map[uint]time.Time),
	}
}

// Agent Script Template
const agentScriptTmpl = `#!/bin/bash
SERVER_URL="{{.ServerURL}}"
SECRET="{{.Secret}}"
HOST_ID="{{.HostID}}"

while true; do
  # Collect Metrics
  
  # Uptime (seconds)
  uptime=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)
  
  # Load
  load=$(cat /proc/loadavg | awk '{print $1}')
  
  # CPU Usage (grep 'cpu ' /proc/stat) - Simplified calculation
  # Previous
  cpu1=$(grep 'cpu ' /proc/stat)
  prev_idle=$(echo "$cpu1" | awk '{print $5}')
  prev_total=$(echo "$cpu1" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
  sleep 1
  # Current
  cpu2=$(grep 'cpu ' /proc/stat)
  idle=$(echo "$cpu2" | awk '{print $5}')
  total=$(echo "$cpu2" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
  
  diff_idle=$((idle - prev_idle))
  diff_total=$((total - prev_total))
  if [ "$diff_total" -eq 0 ]; then diff_total=1; fi
  cpu_usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))
  if [ "$cpu_usage" -lt 0 ]; then cpu_usage=0; fi

  # Memory (Bytes)
  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')
  mem_free=$(grep MemFree /proc/meminfo | awk '{print $2 * 1024}')
  mem_buffers=$(grep Buffers /proc/meminfo | awk '{print $2 * 1024}')
  mem_cached=$(grep ^Cached /proc/meminfo | awk '{print $2 * 1024}')
  # Used = Total - Free - Buffers - Cached
  # Calculate derived values
  if [ -z "$mem_buffers" ]; then mem_buffers=0; fi
  if [ -z "$mem_cached" ]; then mem_cached=0; fi
  if [ -z "$mem_total" ]; then mem_total=0; fi
  if [ -z "$mem_free" ]; then mem_free=0; fi
  mem_used=$((mem_total - mem_free - mem_buffers - mem_cached))

  # Disk (Bytes) - Root partition
  disk_total=$(df -B1 / 2>/dev/null | tail -1 | awk '{print $2}')
  disk_used=$(df -B1 / 2>/dev/null | tail -1 | awk '{print $3}')
  if [ -z "$disk_total" ]; then disk_total=0; fi
  if [ -z "$disk_used" ]; then disk_used=0; fi

  # Network (Bytes)
  net_rx=$(cat /proc/net/dev 2>/dev/null | grep -v lo | awk '{sum+=$2} END {printf "%.0f", sum}')
  net_tx=$(cat /proc/net/dev 2>/dev/null | grep -v lo | awk '{sum+=$10} END {printf "%.0f", sum}')
  if [ -z "$net_rx" ]; then net_rx=0; fi
  if [ -z "$net_tx" ]; then net_tx=0; fi
  
  if [ -z "$uptime" ]; then uptime=0; fi
  if [ -z "$cpu_usage" ]; then cpu_usage=0; fi

  # OS Info
  if [ -f /etc/os-release ]; then
    os=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
  else
    os=$(uname -s)
  fi
  hostname=$(hostname)

  # Check if curl exists
  if ! command -v curl &> /dev/null; then
     # Try wget? No complex logic for now
     sleep 10
     continue
  fi

  # Send Data
  JSON_DATA=$(cat <<EOF
{
  "host_id": $HOST_ID,
  "uptime": $uptime,
  "cpu": $cpu_usage,
  "mem_used": $mem_used,
  "mem_total": $mem_total,
  "disk_used": $disk_used,
  "disk_total": $disk_total,
  "net_rx": $net_rx,
  "net_tx": $net_tx,
  "os": "$os",
  "hostname": "$hostname"
}
EOF
)

  curl -s -X POST "$SERVER_URL/api/monitor/pulse" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $SECRET" \
    -d "$JSON_DATA"

  sleep 2
done
`

// Pulse receives metrics from agents
func (h *MonitorHandler) Pulse(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	secret := authHeader[7:]

	var data monitor.MetricData
	if err := c.ShouldBindJSON(&data); err != nil {
		log.Printf("Monitor Pulse: Bind JSON failed: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Host and Secret
	var host models.SSHHost
	if err := h.DB.Select("*").First(&host, data.HostID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
		return
	}

	if !host.MonitorEnabled || host.MonitorSecret != secret {
		c.JSON(http.StatusForbidden, gin.H{"error": "Invalid secret or monitoring disabled"})
		return
	}

	// Network Traffic Calculation
	var currentRx, currentTx uint64

	// 1. Determine which interface to track
	if host.NetInterface != "" && host.NetInterface != "auto" {
		targetInterfaces := strings.Split(host.NetInterface, ",")
		foundAny := false

		for _, target := range targetInterfaces {
			target = strings.TrimSpace(target)
			for _, iface := range data.Interfaces {
				if iface.Name == target {
					currentRx += iface.Rx
					currentTx += iface.Tx
					foundAny = true
					break // Found this target, move to next target
				}
			}
		}

		// If specified interfaces not found, fallback to total or keep 0?
		// Better fallback to total to avoid plotting 0 if config is stale.
		if !foundAny {
			currentRx = data.NetRx
			currentTx = data.NetTx
		}
	} else {
		// Auto: Use Total
		currentRx = data.NetRx
		currentTx = data.NetTx
	}

	// 2. Check for Reset Day logic
	now := time.Now()
	todayStr := now.Format("2006-01-02")

	dbUpdated := false

	// Reset Day Check: If today is reset day and we haven't reset yet today
	if now.Day() == host.NetResetDay && host.NetLastResetDate != todayStr {
		host.NetMonthlyRx = 0
		host.NetMonthlyTx = 0
		host.NetLastResetDate = todayStr
		host.TrafficAlerted = false // Reset alert flag
		dbUpdated = true
	}

	// 3. Delta Calculation (Accumulation)
	var deltaRx, deltaTx uint64

	// If LastRaw is 0 (first run or just reset?), we can't calculate delta reliably if agent is already running high numbers.
	// But usually we set LastRaw = Current on first run.
	// To handle initialization: if LastRaw == 0, assume Delta = 0 (or just skip accumulation for this first tick to be safe against huge spike).
	// But if agent is fresh (0), Delta is 0.
	// If agent is long running, Current is huge. Delta = Current - 0 = Huge.
	// We don't want to add huge "Baseline" to Monthly.
	// So: If NetLastRaw == 0, we just sync LastRaw = Current, and Delta = 0.
	// UNLESS NetMonthly is ALSO 0 (Fresh start), then maybe we want to start from 0?
	// Safest: On first pulse (LastRaw=0), don't accumulate delta, just sync.

	if host.NetLastRawRx > 0 {
		if currentRx >= host.NetLastRawRx {
			deltaRx = currentRx - host.NetLastRawRx
		} else {
			// Reboot detected (Current < Last)
			// Assume all Current is new traffic since reboot
			deltaRx = currentRx
		}
	}
	// If LastRawRx == 0, we treat deltaRx as 0 (skip first tick) to avoid adding existing total counters.

	if host.NetLastRawTx > 0 {
		if currentTx >= host.NetLastRawTx {
			deltaTx = currentTx - host.NetLastRawTx
		} else {
			deltaTx = currentTx
		}
	}

	if deltaRx > 0 || deltaTx > 0 {
		host.NetMonthlyRx += deltaRx
		host.NetMonthlyTx += deltaTx
		dbUpdated = true

		// Check Traffic Threshold
		if host.NetTrafficLimit > 0 {
			totalUsed := host.NetMonthlyRx + host.NetMonthlyTx
			// Careful with overflow if limit is huge? uint64 is fine.
			// Calculate percentage
			percent := uint64(0)
			if host.NetTrafficLimit > 0 {
				percent = totalUsed * 100 / host.NetTrafficLimit
			}

			threshold := uint64(host.NotifyTrafficThreshold)
			if threshold == 0 {
				threshold = 90
			} // Default

			if host.NotifyTrafficEnabled && percent >= threshold && !host.TrafficAlerted {
				host.TrafficAlerted = true
				dbUpdated = true
				// Send Notification
				msg := fmt.Sprintf("Host '%s' (ID: %d) has used %d%% of its traffic limit.\nUsed: %s / %s",
					host.Name, host.ID, percent,
					utils.FormatBytes(totalUsed), utils.FormatBytes(host.NetTrafficLimit))

				utils.SendNotification(h.DB, host, fmt.Sprintf("Traffic Warning: %s", host.Name), msg)
			}
		}
	}

	// Always update LastRaw
	if host.NetLastRawRx != currentRx || host.NetLastRawTx != currentTx {
		host.NetLastRawRx = currentRx
		host.NetLastRawTx = currentTx
		dbUpdated = true
	}

	// Update Monitor Status (Heartbeat)
	host.LastPulse = time.Now()
	if host.Status != "online" {
		host.Status = "online"
		// Record "Coming Online" event
		go func(hostID uint) {
			h.DB.Create(&models.MonitorStatusLog{
				HostID:    hostID,
				Status:    "online",
				CreatedAt: time.Now(),
			})
		}(host.ID)

		// Send Back Online Notification
		if host.NotifyOfflineEnabled {
			utils.SendNotification(h.DB, host,
				fmt.Sprintf("Host Back Online: %s", host.Name),
				fmt.Sprintf("Host '%s' (ID: %d) is back online.", host.Name, host.ID),
			)
		}

		dbUpdated = true
	}

	if dbUpdated {
		h.DB.Save(&host)
	}

	// 4. Update Data for View
	data.NetMonthlyRx = host.NetMonthlyRx
	data.NetMonthlyTx = host.NetMonthlyTx
	// Pass Config to Frontend
	data.NetTrafficLimit = host.NetTrafficLimit
	data.NetTrafficUsedAdjustment = host.NetTrafficUsedAdjustment
	data.NetTrafficCounterMode = host.NetTrafficCounterMode

	// DEBUG: Print values to verify logic
	log.Printf("VERIFY_ME HOST %d: MonthlyRx=%d (DeltaRx=%d), LastRawRx=%d, CurrentRx=%d", host.ID, host.NetMonthlyRx, deltaRx, host.NetLastRawRx, currentRx)
	log.Printf("VERIFY_ME DATA TO HUB: NetMonthlyRx=%d", data.NetMonthlyRx)
	// Debug Log
	for _, iface := range data.Interfaces {
		if len(iface.IPs) > 0 || iface.Mac != "" {
			log.Printf("Host %d Iface %s: MAC=%s IPs=%v\n", data.HostID, iface.Name, iface.Mac, iface.IPs)
		}
	}
	monitor.GlobalHub.Update(data)

	// Save to DB periodically (e.g. every minute)
	h.saveMu.Lock()
	lastSave, exists := h.lastDbSave[data.HostID]
	shouldSave := !exists || time.Since(lastSave) > 1*time.Minute
	if shouldSave {
		h.lastDbSave[data.HostID] = time.Now()
	}
	h.saveMu.Unlock()

	if shouldSave {
		go func(d monitor.MetricData) {
			record := models.MonitorRecord{
				HostID:    d.HostID,
				CPU:       d.CPU,
				MemUsed:   d.MemUsed,
				MemTotal:  d.MemTotal,
				DiskUsed:  d.DiskUsed,
				DiskTotal: d.DiskTotal,
				NetRx:     d.NetRx,
				NetTx:     d.NetTx,
			}
			h.DB.Create(&record)
		}(data)
	}

	c.Status(http.StatusOK)
}

// Stream WebSocket for Dashboard
func (h *MonitorHandler) Stream(c *gin.Context) {
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	monitor.GlobalHub.Register(conn)

	// Keep alive loop
	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			monitor.GlobalHub.Unregister(conn)
			break
		}
	}
}

func (h *MonitorHandler) Deploy(c *gin.Context) {
	id := c.Param("id")

	// Parse optional insecure flag
	var req struct {
		Insecure bool `json:"insecure"`
	}
	// We use ShouldBindBodyWith or just ShouldBindJSON.
	// Note: Since this is a POST, we expect JSON body, but params are in URL too.
	// We bind JSON for the flag.
	c.ShouldBindJSON(&req)

	var host models.SSHHost
	if err := h.DB.First(&host, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
		return
	}

	// Generate Secret
	randomBytes := make([]byte, 32)
	rand.Read(randomBytes)
	secret := hex.EncodeToString(randomBytes)

	host.MonitorSecret = secret
	h.DB.Save(&host)

	// Prepare Server URL
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	serverURL := fmt.Sprintf("%s://%s", scheme, c.Request.Host)

	// Connect SSH
	password, _ := utils.DecryptAES(host.PasswordEncrypted, h.Config.Security.EncryptionKey)
	privateKey, _ := utils.DecryptAES(host.PrivateKeyEncrypted, h.Config.Security.EncryptionKey)

	authMethods := []ssh.AuthMethod{}
	if host.AuthType == "key" && privateKey != "" {
		signer, err := ssh.ParsePrivateKey([]byte(privateKey))
		if err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(signer))
		}
	}
	if password != "" {
		authMethods = append(authMethods, ssh.Password(password))
	}

	sshConfig := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // TODO: Use TOFU
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", fmt.Sprintf("%s:%d", host.Host, host.Port), sshConfig)
	if err != nil {
		log.Printf("Monitor Deploy: SSH Dial failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SSH Connection failed: %v", err)})
		return
	}
	defer client.Close()

	// 1. Detect Architecture
	session, _ := client.NewSession()
	output, err := session.Output("uname -m")
	session.Close()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to detect remote architecture"})
		return
	}
	arch := string(bytes.TrimSpace(output))

	// Map uname -m to Go ARCH
	var goArch string
	switch arch {
	case "x86_64", "amd64":
		goArch = "amd64"
	case "aarch64", "arm64":
		goArch = "arm64"
	case "armv7l", "armv7":
		goArch = "arm"
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Unsupported architecture: %s", arch)})
		return
	}

	// Select local binary
	localBinaryPath := fmt.Sprintf("agents/termiscope-agent-linux-%s", goArch)
	// Check if exists
	binaryContent, err := ioutil.ReadFile(localBinaryPath)
	if err != nil {
		log.Printf("Monitor Deploy: Binary not found: %s", localBinaryPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Agent binary for %s not found on server", goArch)})
		return
	}

	// 1.5. Stop existing service (if running) to release file lock
	session, _ = client.NewSession()
	stopCmd := "systemctl stop termiscope-agent || true"
	if host.Username != "root" {
		stopCmd = "echo '" + password + "' | sudo -S sh -c 'systemctl stop termiscope-agent || true'"
	}
	// We ignore errors here because the service might not exist yet
	session.Run(stopCmd)
	session.Close()

	// 2. Setup Directory
	session, _ = client.NewSession()
	setupCmd := "mkdir -p /opt/termiscope/agent"
	if host.Username != "root" {
		setupCmd = "echo '" + password + "' | sudo -S mkdir -p /opt/termiscope/agent"
	}
	if out, err := session.CombinedOutput(setupCmd); err != nil {
		log.Printf("Monitor Deploy: Setup dir failed: %v, Out: %s", err, string(out))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create directory: " + string(out)})
		return
	}
	session.Close()

	// 3. Upload Binary
	remoteBinaryPath := "/opt/termiscope/agent/termiscope-agent"
	uploadPath := remoteBinaryPath
	if host.Username != "root" {
		// Use unique temp file to avoid permission issues if specific file exists owned by root
		uploadPath = fmt.Sprintf("/tmp/termiscope-agent-%d", time.Now().UnixNano())
	}

	session, _ = client.NewSession()
	var stderrBuf bytes.Buffer
	session.Stderr = &stderrBuf

	go func() {
		w, _ := session.StdinPipe()
		w.Write(binaryContent)
		w.Close()
	}()

	if err := session.Run(fmt.Sprintf("cat > %s", uploadPath)); err != nil {
		log.Printf("Monitor Deploy: Upload failed: %v, Stderr: %s", err, stderrBuf.String())
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to upload file to %s: %s", uploadPath, stderrBuf.String())})
		return
	}
	session.Close()

	// 4. Move and Chmod
	if host.Username != "root" {
		session, _ = client.NewSession()
		moveCmd := fmt.Sprintf("echo '%s' | sudo -S mv %s %s", password, uploadPath, remoteBinaryPath)
		if out, err := session.CombinedOutput(moveCmd); err != nil {
			log.Printf("Monitor Deploy: Move failed: %v, Out: %s", err, string(out))
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to move binary: " + string(out)})
			return
		}
		session.Close()
	}

	session, _ = client.NewSession()
	chmodCmd := fmt.Sprintf("chmod +x %s", remoteBinaryPath)
	if host.Username != "root" {
		chmodCmd = fmt.Sprintf("echo '%s' | sudo -S chmod +x %s", password, remoteBinaryPath)
	}
	if out, err := session.CombinedOutput(chmodCmd); err != nil {
		log.Printf("Monitor Deploy: Chmod failed: %v, Out: %s", err, string(out))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to chmod binary: " + string(out)})
		return
	}
	session.Close()

	// 3. Create Systemd Service
	execCmd := fmt.Sprintf("%s -server \"%s\" -secret \"%s\" -id %d", remoteBinaryPath, serverURL, secret, host.ID)
	if req.Insecure {
		execCmd += " -insecure"
	}

	serviceContent := fmt.Sprintf(`[Unit]
Description=TermiScope Monitor Agent
After=network.target

[Service]
ExecStart=%s
Restart=always
User=root
WorkingDirectory=/opt/termiscope/agent

[Install]
WantedBy=multi-user.target
`, execCmd)

	session, _ = client.NewSession()
	var serviceReader bytes.Buffer
	serviceReader.WriteString(serviceContent)

	go func() {
		w, _ := session.StdinPipe()
		w.Write(serviceReader.Bytes())
		w.Close()
	}()

	targetPath := "/etc/systemd/system/termiscope-agent.service"
	if host.Username != "root" {
		targetPath = "/tmp/termiscope-agent.service"
	}

	if err := session.Run(fmt.Sprintf("cat > %s", targetPath)); err != nil {
		log.Printf("Failed to write service file: %v", err)
	}
	session.Close()

	if host.Username != "root" && targetPath == "/tmp/termiscope-agent.service" {
		session, _ := client.NewSession()
		session.Run("echo '" + password + "' | sudo -S mv /tmp/termiscope-agent.service /etc/systemd/system/termiscope-agent.service")
		session.Close()
	}

	// 4. Enable and Start
	session, _ = client.NewSession()
	cmd := "systemctl daemon-reload && systemctl enable --now termiscope-agent"
	if host.Username != "root" {
		cmd = "echo '" + password + "' | sudo -S sh -c '" + cmd + "'"
	}
	output, err = session.CombinedOutput(cmd)
	if err != nil {
		log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to start service: %v", err)})
		return
	}
	session.Close()

	// 5. Update DB
	h.DB.Model(&host).Update("monitor_enabled", true)

	c.JSON(http.StatusOK, gin.H{"message": "Agent deployed successfully"})
}

func (h *MonitorHandler) Stop(c *gin.Context) {
	id := c.Param("id") // Fix: Use correct Param name? Previous code used "id"
	var host models.SSHHost
	if err := h.DB.First(&host, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
		return
	}

	// Notify clients to remove immediately
	monitor.GlobalHub.RemoveHost(host.ID)
	// Update DB immediately
	h.DB.Model(&host).Update("monitor_enabled", false)

	// Connect SSH to stop service
	password, _ := utils.DecryptAES(host.PasswordEncrypted, h.Config.Security.EncryptionKey)
	privateKey, _ := utils.DecryptAES(host.PrivateKeyEncrypted, h.Config.Security.EncryptionKey)

	authMethods := []ssh.AuthMethod{}
	if host.AuthType == "key" && privateKey != "" {
		signer, err := ssh.ParsePrivateKey([]byte(privateKey))
		if err == nil {
			authMethods = append(authMethods, ssh.PublicKeys(signer))
		}
	}
	if password != "" {
		authMethods = append(authMethods, ssh.Password(password))
	}

	sshConfig := &ssh.ClientConfig{
		User:            host.Username,
		Auth:            authMethods,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", fmt.Sprintf("%s:%d", host.Host, host.Port), sshConfig)
	if err != nil {
		// Just log error, basic cleanup manually if needed
		log.Printf("Monitor Stop: SSH Dial failed: %v", err)
		c.JSON(http.StatusOK, gin.H{"message": "Monitoring disabled (Agent stop failed: SSH connection error)"})
		return
	}
	defer client.Close()

	session, _ := client.NewSession()
	defer session.Close()

	cmd := "systemctl disable --now termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload && rm -rf /opt/termiscope/agent"
	if host.Username != "root" {
		cmd = "echo " + password + " | sudo -S sh -c '" + cmd + "'"
	}

	if err := session.Run(cmd); err != nil {
		log.Printf("Monitor Stop: Failed to run cleanup commands: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Monitoring stopped and agent removed"})
}

// GetStatusLogs returns the status history for a host
func (h *MonitorHandler) GetStatusLogs(c *gin.Context) {
	id := c.Param("id")

	// Pagination
	page := utils.GetIntQuery(c, "page", 1)
	pageSize := utils.GetIntQuery(c, "page_size", 20)
	offset := (page - 1) * pageSize

	var logs []models.MonitorStatusLog
	var total int64

	db := h.DB.Model(&models.MonitorStatusLog{}).Where("host_id = ?", id)

	db.Count(&total)

	if err := db.Order("created_at desc").Offset(offset).Limit(pageSize).Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch logs"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data":  logs,
		"total": total,
		"page":  page,
	})
}
