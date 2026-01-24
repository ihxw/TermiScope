package handlers

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"strconv"
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

	// 验证 Secret
	if host.MonitorSecret != secret {
		c.JSON(http.StatusForbidden, gin.H{"error": "Invalid secret"})
		return
	}

	// 如果监控未启用，自动启用（首次收到数据时）
	if !host.MonitorEnabled {
		host.MonitorEnabled = true
		h.DB.Model(&host).Update("monitor_enabled", true)
		log.Printf("Monitor auto-enabled for host %d (%s) on first pulse", host.ID, host.Name)
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

	// Update Agent Version if present
	if data.AgentVersion != "" && host.AgentVersion != data.AgentVersion {
		host.AgentVersion = data.AgentVersion
		dbUpdated = true
	}

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
		h.DB.Model(&host).Select(
			"MonitorEnabled",
			"NetMonthlyRx", "NetMonthlyTx",
			"NetLastRawRx", "NetLastRawTx",
			"NetLastResetDate",
			"TrafficAlerted",
			"AgentVersion",
			"Status",
			"LastPulse",
		).Updates(&host)
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
	// Debug Log - Commented out to reduce noise
	// for _, iface := range data.Interfaces {
	// 	if len(iface.IPs) > 0 || iface.Mac != "" {
	// 		log.Printf("Host %d Iface %s: MAC=%s IPs=%v\n", data.HostID, iface.Name, iface.Mac, iface.IPs)
	// 	}
	// }
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

	// 生成或使用现有的 Secret（永久token）
	secret := host.MonitorSecret
	if secret == "" {
		// 生成新的 Secret
		randomBytes := make([]byte, 32)
		rand.Read(randomBytes)
		secret = hex.EncodeToString(randomBytes)
		host.MonitorSecret = secret
		h.DB.Save(&host)
	}

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

	client, err := ssh.Dial("tcp", net.JoinHostPort(host.Host, strconv.Itoa(host.Port)), sshConfig)
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

	// 3. Detect Init System
	var initSystem string

	// Check for systemd
	session, _ = client.NewSession()
	if session.Run("which systemctl") == nil {
		initSystem = "systemd"
	}
	session.Close()

	// Check for OpenWrt procd
	if initSystem == "" {
		session, _ = client.NewSession()
		if session.Run("test -f /etc/openwrt_release") == nil {
			initSystem = "procd"
		}
		session.Close()
	}

	// Check for Upstart
	if initSystem == "" {
		session, _ = client.NewSession()
		if session.Run("which initctl") == nil {
			initSystem = "upstart"
		}
		session.Close()
	}

	// Check for FreeBSD rc.d
	if initSystem == "" {
		session, _ = client.NewSession()
		if session.Run("test -f /etc/rc.conf") == nil {
			initSystem = "freebsd"
		}
		session.Close()
	}

	// Default to SysV init
	if initSystem == "" {
		initSystem = "sysv"
	}

	log.Printf("Detected init system: %s", initSystem)

	// 4. Create Service based on init system
	execCmd := fmt.Sprintf("%s -server \"%s\" -secret \"%s\" -id %d", remoteBinaryPath, serverURL, secret, host.ID)
	if req.Insecure {
		execCmd += " -insecure"
	}

	switch initSystem {
	case "systemd":
		// Systemd service
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

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "systemctl daemon-reload && systemctl enable --now termiscope-agent"
		if host.Username != "root" {
			cmd = "echo '" + password + "' | sudo -S sh -c '" + cmd + "'"
		}
		output, err = session.CombinedOutput(cmd)
		if err != nil {
			log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":  fmt.Sprintf("Failed to start service: %v", err),
				"output": string(output),
			})
			return
		}
		session.Close()

	case "procd":
		// OpenWrt procd init script
		initScript := fmt.Sprintf(`#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command %s
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
`, execCmd)

		session, _ = client.NewSession()
		var initReader bytes.Buffer
		initReader.WriteString(initScript)

		go func() {
			w, _ := session.StdinPipe()
			w.Write(initReader.Bytes())
			w.Close()
		}()

		if err := session.Run("cat > /etc/init.d/termiscope-agent"); err != nil {
			log.Printf("Failed to write init script: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to write init script"})
			return
		}
		session.Close()

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "chmod +x /etc/init.d/termiscope-agent && /etc/init.d/termiscope-agent enable && /etc/init.d/termiscope-agent start"
		output, err = session.CombinedOutput(cmd)
		if err != nil {
			log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":  fmt.Sprintf("Failed to start service: %v", err),
				"output": string(output),
			})
			return
		}
		session.Close()

	case "upstart":
		// Upstart service (Ubuntu 14.04 等)
		upstartConf := fmt.Sprintf(`description "TermiScope Monitor Agent"
author "TermiScope"

start on runlevel [2345]
stop on runlevel [!2345]

respawn
respawn limit 10 5

exec %s
`, execCmd)

		session, _ = client.NewSession()
		var upstartReader bytes.Buffer
		upstartReader.WriteString(upstartConf)

		go func() {
			w, _ := session.StdinPipe()
			w.Write(upstartReader.Bytes())
			w.Close()
		}()

		targetPath := "/etc/init/termiscope-agent.conf"
		if host.Username != "root" {
			targetPath = "/tmp/termiscope-agent.conf"
		}

		if err := session.Run(fmt.Sprintf("cat > %s", targetPath)); err != nil {
			log.Printf("Failed to write upstart config: %v", err)
		}
		session.Close()

		if host.Username != "root" {
			session, _ := client.NewSession()
			session.Run("echo '" + password + "' | sudo -S mv /tmp/termiscope-agent.conf /etc/init/termiscope-agent.conf")
			session.Close()
		}

		// Start service
		session, _ = client.NewSession()
		cmd := "initctl reload-configuration && initctl start termiscope-agent"
		if host.Username != "root" {
			cmd = "echo '" + password + "' | sudo -S sh -c '" + cmd + "'"
		}
		output, err = session.CombinedOutput(cmd)
		if err != nil {
			log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":  fmt.Sprintf("Failed to start service: %v", err),
				"output": string(output),
			})
			return
		}
		session.Close()

	case "freebsd":
		// FreeBSD rc.d service
		rcScript := fmt.Sprintf(`#!/bin/sh
# PROVIDE: termiscope_agent
# REQUIRE: NETWORKING
# KEYWORD: shutdown

. /etc/rc.subr

name="termiscope_agent"
rcvar="${name}_enable"

command="%s"
pidfile="/var/run/${name}.pid"

load_rc_config $name
: ${termiscope_agent_enable:=NO}

run_rc_command "$1"
`, execCmd)

		session, _ = client.NewSession()
		var rcReader bytes.Buffer
		rcReader.WriteString(rcScript)

		go func() {
			w, _ := session.StdinPipe()
			w.Write(rcReader.Bytes())
			w.Close()
		}()

		if err := session.Run("cat > /usr/local/etc/rc.d/termiscope_agent"); err != nil {
			log.Printf("Failed to write rc.d script: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to write rc.d script"})
			return
		}
		session.Close()

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "chmod +x /usr/local/etc/rc.d/termiscope_agent && sysrc termiscope_agent_enable=YES && service termiscope_agent start"
		output, err = session.CombinedOutput(cmd)
		if err != nil {
			log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":  fmt.Sprintf("Failed to start service: %v", err),
				"output": string(output),
			})
			return
		}
		session.Close()

	case "sysv":
		// SysV init script (CentOS 6, Debian 7 等)
		sysvScript := fmt.Sprintf(`#!/bin/bash
### BEGIN INIT INFO
# Provides:          termiscope-agent
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: TermiScope Monitor Agent
# Description:       TermiScope monitoring agent service
### END INIT INFO

DAEMON=%s
PIDFILE=/var/run/termiscope-agent.pid
NAME=termiscope-agent

start() {
    echo "Starting $NAME..."
    nohup $DAEMON > /dev/null 2>&1 &
    echo $! > $PIDFILE
}

stop() {
    echo "Stopping $NAME..."
    if [ -f $PIDFILE ]; then
        kill $(cat $PIDFILE)
        rm -f $PIDFILE
    fi
}

restart() {
    stop
    sleep 1
    start
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
esac
`, remoteBinaryPath)

		session, _ = client.NewSession()
		var sysvReader bytes.Buffer
		sysvReader.WriteString(sysvScript)

		go func() {
			w, _ := session.StdinPipe()
			w.Write(sysvReader.Bytes())
			w.Close()
		}()

		targetPath := "/etc/init.d/termiscope-agent"
		if host.Username != "root" {
			targetPath = "/tmp/termiscope-agent"
		}

		if err := session.Run(fmt.Sprintf("cat > %s", targetPath)); err != nil {
			log.Printf("Failed to write init script: %v", err)
		}
		session.Close()

		if host.Username != "root" {
			session, _ := client.NewSession()
			session.Run("echo '" + password + "' | sudo -S mv /tmp/termiscope-agent /etc/init.d/termiscope-agent")
			session.Close()
		}

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "chmod +x /etc/init.d/termiscope-agent && "
		// Try chkconfig first (CentOS/RHEL), then update-rc.d (Debian/Ubuntu)
		cmd += "(chkconfig --add termiscope-agent && chkconfig termiscope-agent on || update-rc.d termiscope-agent defaults) && "
		cmd += "/etc/init.d/termiscope-agent start"
		if host.Username != "root" {
			cmd = "echo '" + password + "' | sudo -S sh -c '" + cmd + "'"
		}
		output, err = session.CombinedOutput(cmd)
		if err != nil {
			log.Printf("Monitor Deploy: Failed to start service: %v, Output: %s", err, string(output))
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":  fmt.Sprintf("Failed to start service: %v", err),
				"output": string(output),
			})
			return
		}
		session.Close()
	}

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

// BatchDeployRequest - 批量部署请求
type BatchDeployRequest struct {
	HostIDs  []uint `json:"host_ids" binding:"required"`
	Insecure bool   `json:"insecure"`
}

// BatchDeployResult - 单个主机部署结果
type BatchDeployResult struct {
	HostID   uint   `json:"host_id"`
	HostName string `json:"host_name"`
	Success  bool   `json:"success"`
	Message  string `json:"message"`
}

// BatchDeploy - 批量部署agent到多个主机
func (h *MonitorHandler) BatchDeploy(c *gin.Context) {
	var req BatchDeployRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(req.HostIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no hosts specified"})
		return
	}

	results := make([]BatchDeployResult, 0, len(req.HostIDs))

	// 并发部署(限制并发数避免资源耗尽)
	maxConcurrent := 5
	semaphore := make(chan struct{}, maxConcurrent)
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, hostID := range req.HostIDs {
		wg.Add(1)
		go func(id uint) {
			defer wg.Done()
			semaphore <- struct{}{}        // 获取信号量
			defer func() { <-semaphore }() // 释放信号量

			result := BatchDeployResult{HostID: id}

			// 获取主机信息
			var host models.SSHHost
			if err := h.DB.First(&host, id).Error; err != nil {
				result.Success = false
				result.Message = "主机不存在"
				mu.Lock()
				results = append(results, result)
				mu.Unlock()
				return
			}

			result.HostName = host.Name

			// 执行部署
			err := h.deployToHost(&host, req.Insecure, c.Request)
			if err != nil {
				result.Success = false
				result.Message = err.Error()
			} else {
				result.Success = true
				result.Message = "部署成功"
			}

			mu.Lock()
			results = append(results, result)
			mu.Unlock()
		}(hostID)
	}

	wg.Wait()

	c.JSON(http.StatusOK, gin.H{
		"results": results,
	})
}

// deployToHost - 部署agent到指定主机(从Deploy函数提取的核心逻辑)
func (h *MonitorHandler) deployToHost(host *models.SSHHost, insecure bool, request *http.Request) error {
	// Generate Secret
	randomBytes := make([]byte, 32)
	rand.Read(randomBytes)
	secret := hex.EncodeToString(randomBytes)

	host.MonitorSecret = secret
	h.DB.Save(host)

	// Prepare Server URL
	scheme := "http"
	if request.TLS != nil || request.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	serverURL := fmt.Sprintf("%s://%s", scheme, request.Host)

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
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         10 * time.Second,
	}

	client, err := ssh.Dial("tcp", fmt.Sprintf("%s:%d", host.Host, host.Port), sshConfig)
	if err != nil {
		return fmt.Errorf("SSH连接失败: %v", err)
	}
	defer client.Close()

	// Detect Architecture
	session, _ := client.NewSession()
	output, err := session.Output("uname -m")
	session.Close()
	if err != nil {
		return fmt.Errorf("检测架构失败: %v", err)
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
		return fmt.Errorf("不支持的架构: %s", arch)
	}

	// Select local binary
	localBinaryPath := fmt.Sprintf("agents/termiscope-agent-linux-%s", goArch)
	binaryContent, err := ioutil.ReadFile(localBinaryPath)
	if err != nil {
		return fmt.Errorf("Agent二进制文件不存在: %s", goArch)
	}

	// Stop existing service
	session, _ = client.NewSession()
	stopCmd := "systemctl stop termiscope-agent || true"
	if host.Username != "root" {
		stopCmd = "echo '" + password + "' | sudo -S sh -c 'systemctl stop termiscope-agent || true'"
	}
	session.Run(stopCmd)
	session.Close()

	// Setup Directory
	session, _ = client.NewSession()
	setupCmd := "mkdir -p /opt/termiscope/agent"
	if host.Username != "root" {
		setupCmd = "echo '" + password + "' | sudo -S mkdir -p /opt/termiscope/agent"
	}
	if out, err := session.CombinedOutput(setupCmd); err != nil {
		return fmt.Errorf("创建目录失败: %s", string(out))
	}
	session.Close()

	// Upload Binary
	remoteBinaryPath := "/opt/termiscope/agent/termiscope-agent"
	uploadPath := remoteBinaryPath
	if host.Username != "root" {
		uploadPath = fmt.Sprintf("/tmp/termiscope-agent-%d", time.Now().UnixNano())
	}

	session, _ = client.NewSession()
	go func() {
		w, _ := session.StdinPipe()
		w.Write(binaryContent)
		w.Close()
	}()

	if err := session.Run(fmt.Sprintf("cat > %s", uploadPath)); err != nil {
		return fmt.Errorf("上传agent失败")
	}
	session.Close()

	// Move and Chmod
	if host.Username != "root" {
		session, _ = client.NewSession()
		moveCmd := fmt.Sprintf("echo '%s' | sudo -S mv %s %s", password, uploadPath, remoteBinaryPath)
		if out, err := session.CombinedOutput(moveCmd); err != nil {
			return fmt.Errorf("移动文件失败: %s", string(out))
		}
		session.Close()
	}

	session, _ = client.NewSession()
	chmodCmd := fmt.Sprintf("chmod +x %s", remoteBinaryPath)
	if host.Username != "root" {
		chmodCmd = fmt.Sprintf("echo '%s' | sudo -S chmod +x %s", password, remoteBinaryPath)
	}
	if out, err := session.CombinedOutput(chmodCmd); err != nil {
		return fmt.Errorf("设置权限失败: %s", string(out))
	}
	session.Close()

	// Create Systemd Service
	execCmd := fmt.Sprintf("%s -server \"%s\" -secret \"%s\" -id %d", remoteBinaryPath, serverURL, secret, host.ID)
	if insecure {
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

	session.Run(fmt.Sprintf("cat > %s", targetPath))
	session.Close()

	if host.Username != "root" && targetPath == "/tmp/termiscope-agent.service" {
		session, _ := client.NewSession()
		session.Run("echo '" + password + "' | sudo -S mv /tmp/termiscope-agent.service /etc/systemd/system/termiscope-agent.service")
		session.Close()
	}

	// Enable and Start
	session, _ = client.NewSession()
	cmd := "systemctl daemon-reload && systemctl enable --now termiscope-agent"
	if host.Username != "root" {
		cmd = "echo '" + password + "' | sudo -S sh -c '" + cmd + "'"
	}
	output, err = session.CombinedOutput(cmd)
	if err != nil {
		return fmt.Errorf("启动服务失败: %v", err)
	}
	session.Close()

	// Update DB
	h.DB.Model(host).Update("monitor_enabled", true)

	return nil
}

// BatchStopRequest - 批量停止监控请求
type BatchStopRequest struct {
	HostIDs []uint `json:"host_ids" binding:"required"`
}

// BatchStopResult - 单个主机停止结果
type BatchStopResult struct {
	HostID   uint   `json:"host_id"`
	HostName string `json:"host_name"`
	Success  bool   `json:"success"`
	Message  string `json:"message"`
}

// BatchStop - 批量停止监控
func (h *MonitorHandler) BatchStop(c *gin.Context) {
	var req BatchStopRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(req.HostIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no hosts specified"})
		return
	}

	results := make([]BatchStopResult, 0, len(req.HostIDs))

	// 并发停止(限制并发数)
	maxConcurrent := 5
	semaphore := make(chan struct{}, maxConcurrent)
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, hostID := range req.HostIDs {
		wg.Add(1)
		go func(id uint) {
			defer wg.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			result := BatchStopResult{HostID: id}

			// 获取主机信息
			var host models.SSHHost
			if err := h.DB.First(&host, id).Error; err != nil {
				result.Success = false
				result.Message = "主机不存在"
				mu.Lock()
				results = append(results, result)
				mu.Unlock()
				return
			}

			result.HostName = host.Name

			// 执行停止
			err := h.stopMonitorOnHost(&host)
			if err != nil {
				result.Success = false
				result.Message = err.Error()
			} else {
				result.Success = true
				result.Message = "停止成功"
			}

			mu.Lock()
			results = append(results, result)
			mu.Unlock()
		}(hostID)
	}

	wg.Wait()

	c.JSON(http.StatusOK, gin.H{
		"results": results,
	})
}

// stopMonitorOnHost - 停止指定主机的监控(从Stop函数提取的核心逻辑)
func (h *MonitorHandler) stopMonitorOnHost(host *models.SSHHost) error {
	// Update DB first
	h.DB.Model(host).Update("monitor_enabled", false)

	// Try to cleanup on remote host
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
		// SSH连接失败不算错误,因为DB已经更新
		log.Printf("Monitor BatchStop: SSH连接失败(已更新DB): %v", err)
		return nil
	}
	defer client.Close()

	// Stop and disable service
	session, _ := client.NewSession()
	cmd := "systemctl stop termiscope-agent && systemctl disable termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload"
	if host.Username != "root" {
		cmd = "echo " + password + " | sudo -S sh -c '" + cmd + "'"
	}

	session.Run(cmd)
	session.Close()

	return nil
}

// GetInstallScript 生成一键安装脚本
func (h *MonitorHandler) GetInstallScript(c *gin.Context) {
	hostID := c.Query("host_id")
	secret := c.Query("secret")

	if hostID == "" || secret == "" {
		c.String(http.StatusBadRequest, "#!/bin/bash\necho 'Error: host_id and secret parameters are required'\nexit 1")
		return
	}

	// 获取主机信息并验证 secret
	var host models.SSHHost
	if err := h.DB.First(&host, hostID).Error; err != nil {
		c.String(http.StatusNotFound, "#!/bin/bash\necho 'Error: Host not found'\nexit 1")
		return
	}

	// 验证 secret
	if host.MonitorSecret != secret {
		c.String(http.StatusForbidden, "#!/bin/bash\necho 'Error: Invalid secret'\nexit 1")
		return
	}

	// 生成或使用现有的 Secret（这里 secret 已经验证过，直接使用）
	if host.MonitorSecret == "" {
		// 这种情况理论上不会发生，因为上面已经验证了
		randomBytes := make([]byte, 32)
		rand.Read(randomBytes)
		host.MonitorSecret = hex.EncodeToString(randomBytes)
		h.DB.Save(&host)
		secret = host.MonitorSecret
	}

	// 获取服务器 URL
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	serverURL := fmt.Sprintf("%s://%s", scheme, c.Request.Host)

	// 生成安装脚本
	// 读取模板文件
	tmplContent, err := ioutil.ReadFile("scripts/install_agent.sh.tmpl")
	if err != nil {
		log.Printf("Failed to read install script template: %v", err)
		c.String(http.StatusInternalServerError, "#!/bin/bash\necho 'Error: Failed to read installation template'\nexit 1")
		return
	}

	script := string(tmplContent)
	script = strings.ReplaceAll(script, "{{HOST_NAME}}", host.Name)
	script = strings.ReplaceAll(script, "{{HOST_ID}}", hostID)
	script = strings.ReplaceAll(script, "{{SERVER_URL}}", serverURL)
	script = strings.ReplaceAll(script, "{{SECRET}}", secret)

	// 强制转换 CRLF 为 LF，解决 Windows/Linux 换行符兼容性问题
	script = strings.ReplaceAll(script, "\r\n", "\n")

	c.Header("Content-Type", "text/plain; charset=utf-8")
	c.String(http.StatusOK, script)
}

// GetUninstallScript 生成卸载脚本
func (h *MonitorHandler) GetUninstallScript(c *gin.Context) {
	// 获取参数（如果通过前端生成的链接访问）
	secret := c.Query("secret")
	hostID := c.Query("host_id")

	// 获取服务器 URL
	scheme := "http"
	if c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	serverURL := fmt.Sprintf("%s://%s", scheme, c.Request.Host)

	// 读取模板文件
	tmplContent, err := ioutil.ReadFile("scripts/uninstall_agent.sh.tmpl")
	if err != nil {
		log.Printf("Failed to read uninstall script template: %v", err)
		c.String(http.StatusInternalServerError, "#!/bin/bash\necho 'Error: Failed to read uninstall template'\nexit 1")
		return
	}

	script := string(tmplContent)
	// 替换变量
	script = strings.ReplaceAll(script, "{{HOST_ID}}", hostID)
	script = strings.ReplaceAll(script, "{{SERVER_URL}}", serverURL)
	script = strings.ReplaceAll(script, "{{SECRET}}", secret)

	// 强制转换 CRLF 为 LF
	script = strings.ReplaceAll(script, "\r\n", "\n")

	c.Header("Content-Type", "text/plain; charset=utf-8")
	c.String(http.StatusOK, script)
}

// UninstallCallback 处理卸载回调
func (h *MonitorHandler) UninstallCallback(c *gin.Context) {
	secret := c.Query("secret")
	hostID := c.Query("host_id")

	if secret == "" || hostID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "secret and host_id required"})
		return
	}

	var host models.SSHHost
	if err := h.DB.First(&host, hostID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "host not found"})
		return
	}

	if host.MonitorSecret != secret {
		c.JSON(http.StatusForbidden, gin.H{"error": "invalid secret"})
		return
	}

	// 更新状态为未启用监控
	h.DB.Model(&host).Update("monitor_enabled", false)
	c.JSON(http.StatusOK, gin.H{"success": true})
}

// DownloadAgent 提供 agent 二进制文件下载
func (h *MonitorHandler) DownloadAgent(c *gin.Context) {
	filename := c.Param("filename")
	secret := c.Query("secret")
	hostID := c.Query("host_id")

	// 验证参数
	if secret == "" || hostID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "secret and host_id parameters are required"})
		return
	}

	// 验证 secret
	var host models.SSHHost
	if err := h.DB.First(&host, hostID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
		return
	}

	if host.MonitorSecret != secret {
		c.JSON(http.StatusForbidden, gin.H{"error": "Invalid secret"})
		return
	}

	// 验证文件名，防止路径遍历攻击
	if strings.Contains(filename, "..") || strings.Contains(filename, "/") || strings.Contains(filename, "\\") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filename"})
		return
	}

	// 构建文件路径
	filePath := fmt.Sprintf("agents/%s", filename)

	// 检查文件是否存在
	if _, err := ioutil.ReadFile(filePath); err != nil {
		log.Printf("Agent file not found: %s", filePath)
		c.JSON(http.StatusNotFound, gin.H{"error": "Agent binary not found"})
		return
	}

	// 设置响应头
	c.Header("Content-Description", "File Transfer")
	c.Header("Content-Transfer-Encoding", "binary")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Type", "application/octet-stream")

	// 发送文件
	c.File(filePath)
}
