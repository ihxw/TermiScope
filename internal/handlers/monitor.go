package handlers

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/monitor"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type MonitorHandler struct {
	DB           *gorm.DB
	Config       *config.Config
	lastDbSave   map[uint]time.Time
	saveMu       sync.Mutex
	pulseMu      map[uint]*sync.Mutex
	pulseMuGuard sync.Mutex
}

func NewMonitorHandler(db *gorm.DB, cfg *config.Config) *MonitorHandler {
	handler := &MonitorHandler{
		DB:         db,
		Config:     cfg,
		lastDbSave: make(map[uint]time.Time),
		pulseMu:    make(map[uint]*sync.Mutex),
	}

	// Start the hub
	go monitor.GlobalHub.Run()
	monitor.OnHostRemoved(handler.cleanupHostPulseState)

	// Start Cleanup Routine (network results 24h; monitor_records 8d)
	go func() {
		database.RunMonitorRecordsMaintenance(db)
		ticker := time.NewTicker(1 * time.Hour)
		for range ticker.C {
			database.RunNetworkMonitorMaintenance(db, cfg.Security.EncryptionKey)
			database.RunMonitorRecordsMaintenance(db)
		}
	}()

	// Start Traffic Reset Scheduler (every hour, check all hosts)
	go handler.startTrafficResetScheduler()

	return handler
}

// startTrafficResetScheduler runs a background goroutine that periodically checks
// all monitored hosts and resets traffic counters when a new billing cycle starts.
// This ensures resets happen even if the agent is temporarily offline.
func (h *MonitorHandler) startTrafficResetScheduler() {
	// Run once on startup (short delay to allow DB init)
	time.Sleep(10 * time.Second)
	h.checkAllHostsTrafficReset()

	ticker := time.NewTicker(1 * time.Hour)
	for range ticker.C {
		h.checkAllHostsTrafficReset()
	}
}

// checkAllHostsTrafficReset iterates all monitored hosts and resets traffic if needed.
func (h *MonitorHandler) checkAllHostsTrafficReset() {
	var hosts []models.SSHHost
	if err := h.DB.Where("monitor_enabled = ?", true).Find(&hosts).Error; err != nil {
		log.Printf("Traffic Reset Scheduler: Failed to load hosts: %v", err)
		return
	}

	log.Printf("Traffic Reset Scheduler: Checking %d hosts", len(hosts))
	for i := range hosts {
		cycleStart := getCycleStartDate(time.Now(), hosts[i].NetResetDay)
		log.Printf("Traffic Reset Scheduler: Host %d (%s) ResetDay=%d LastResetDate='%s' CycleStart='%s' MonthlyRx=%d MonthlyTx=%d",
			hosts[i].ID, hosts[i].Name, hosts[i].NetResetDay, hosts[i].NetLastResetDate, cycleStart,
			hosts[i].NetMonthlyRx, hosts[i].NetMonthlyTx)
		if h.checkAndResetTraffic(&hosts[i]) {
			log.Printf("Traffic Reset Scheduler: Reset completed for Host %d (%s)", hosts[i].ID, hosts[i].Name)
		}
	}
}

// getCycleStartDate calculates the current billing cycle start date for a given reset day.
func getCycleStartDate(now time.Time, resetDay int) string {
	if resetDay == 0 {
		resetDay = 1
	}

	year, month, day := now.Date()

	// Helper to safely get the effective reset day for a given month
	getEffectiveResetDay := func(y int, m time.Month) int {
		lastDay := time.Date(y, m+1, 0, 0, 0, 0, 0, time.Local).Day()
		if resetDay > lastDay {
			return lastDay
		}
		return resetDay
	}

	effectiveResetDay := getEffectiveResetDay(year, month)

	var currentCycleStart time.Time
	if day >= effectiveResetDay {
		currentCycleStart = time.Date(year, month, effectiveResetDay, 0, 0, 0, 0, time.Local)
	} else {
		// Calculate the effective reset day for the previous month
		prevMonth := month - 1
		prevYear := year
		if prevMonth == 0 {
			prevMonth = 12
			prevYear--
		}
		prevEffectiveResetDay := getEffectiveResetDay(prevYear, prevMonth)
		currentCycleStart = time.Date(prevYear, prevMonth, prevEffectiveResetDay, 0, 0, 0, 0, time.Local)
	}

	return currentCycleStart.Format("2006-01-02")
}

func (h *MonitorHandler) hasSuccessfulResetLog(hostID uint, resetDate string) bool {
	var logCount int64
	h.DB.Model(&models.MonitorTrafficResetLog{}).
		Where("host_id = ? AND reset_date = ? AND status = 'success'", hostID, resetDate).
		Limit(1).
		Count(&logCount)
	return logCount > 0
}

// checkAndResetTraffic checks if a host needs traffic reset and performs it.
// Returns true if a reset was performed, false otherwise.
// This method is safe to call from both Pulse() and the background scheduler.
func (h *MonitorHandler) checkAndResetTraffic(host *models.SSHHost) bool {
	currentCycleStartStr := getCycleStartDate(time.Now(), host.NetResetDay)

	// Determine if reset is needed by comparing date strings (YYYY-MM-DD, lexicographic order)
	shouldReset := false
	if host.NetLastResetDate == "" {
		shouldReset = true
	} else if host.NetLastResetDate < currentCycleStartStr {
		shouldReset = true
	}

	// Fallback: even if date matches current cycle, check if reset log exists.
	if !shouldReset && host.NetLastResetDate == currentCycleStartStr {
		if !h.hasSuccessfulResetLog(host.ID, currentCycleStartStr) {
			shouldReset = true
			log.Printf("Traffic Reset: Host %d date matches cycle %s but no reset log found, forcing reset",
				host.ID, currentCycleStartStr)
		}
	}

	if !shouldReset {
		return false
	}

	log.Printf("Traffic Reset Check: Host %d, LastResetDate=%s, CurrentCycleStart=%s, ShouldReset=true",
		host.ID, host.NetLastResetDate, currentCycleStartStr)

	var logCount int64
	if h.hasSuccessfulResetLog(host.ID, currentCycleStartStr) {
		logCount = 1
	}

	if logCount > 0 {
		// Already reset in DB with log. Safe to skip.
		host.NetLastResetDate = currentCycleStartStr
		log.Printf("Traffic Reset: Host %d already has reset log for %s, skipping.",
			host.ID, currentCycleStartStr)
		return false
	}

	// Real Reset Needed - Execute in Transaction
	var alreadyReset bool
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		// Double check inside transaction to prevent race conditions
		var count int64
		tx.Model(&models.MonitorTrafficResetLog{}).
			Where("host_id = ? AND reset_date = ? AND status = 'success'", host.ID, currentCycleStartStr).
			Count(&count)
		if count > 0 {
			alreadyReset = true
			return nil
		}

		if err := tx.Model(host).Updates(map[string]interface{}{
			"net_monthly_rx":              0,
			"net_monthly_tx":              0,
			"net_traffic_used_adjustment": 0,
			"net_last_raw_rx":             0,
			"net_last_raw_tx":             0,
			"net_last_reset_date":         currentCycleStartStr,
			"traffic_alerted":             false,
		}).Error; err != nil {
			return err
		}

		if err := tx.Create(&models.MonitorTrafficResetLog{
			HostID:    host.ID,
			ResetDate: currentCycleStartStr,
			Status:    "success",
			CreatedAt: time.Now(),
		}).Error; err != nil {
			return err
		}
		return nil
	})

	if err != nil {
		log.Printf("Traffic Reset Transaction FAILED for Host %d: %v", host.ID, err)
		return false
	}

	if alreadyReset {
		host.NetLastResetDate = currentCycleStartStr
		return false
	}

	// Success: Update in-memory host to reflect DB
	host.NetMonthlyRx = 0
	host.NetMonthlyTx = 0
	host.NetTrafficUsedAdjustment = 0
	host.NetLastRawRx = 0
	host.NetLastRawTx = 0
	host.NetLastResetDate = currentCycleStartStr
	host.TrafficAlerted = false
	log.Printf("Traffic Reset Transaction SUCCESS for Host %d: New Cycle %s", host.ID, currentCycleStartStr)
	return true
}

func (h *MonitorHandler) lockHostPulse(hostID uint) func() {
	h.pulseMuGuard.Lock()
	mu, ok := h.pulseMu[hostID]
	if !ok {
		mu = &sync.Mutex{}
		h.pulseMu[hostID] = mu
	}
	h.pulseMuGuard.Unlock()
	mu.Lock()
	return mu.Unlock
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

	# Disk (Bytes) - All real mounted partitions
  disk_total=0
  disk_used=0
  disks_json="["
  first_disk=1
	declare -A seen_disk_keys
	# -P: POSIX output (one line per FS, no wrapping for long device names like /dev/mapper/...)
	# -T: include filesystem type so we can filter pseudo filesystems reliably.
  while IFS= read -r dfline; do
		# df -B1 -P -T columns: Filesystem, Type, 1B-blocks, Used, Available, Capacity%, Mounted
    dfs=$(echo "$dfline" | awk '{print $1}')
		dffstype=$(echo "$dfline" | awk '{print $2}')
		dft=$(echo "$dfline" | awk '{print $3}')
		dfu=$(echo "$dfline" | awk '{print $4}')
		dfm=$(echo "$dfline" | awk '{print $7}')
    # Skip if any field is empty or total is 0
		if [ -z "$dfs" ] || [ -z "$dffstype" ] || [ -z "$dft" ] || [ -z "$dfu" ] || [ -z "$dfm" ]; then continue; fi
    if [ "$dft" -eq 0 ] 2>/dev/null; then continue; fi
    # Skip virtual/pseudo mount points
    case "$dfm" in /proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*|/snap/*) continue ;; esac
		# Skip pseudo filesystem types. Keep overlay only when it is the root filesystem.
		case "$dffstype" in tmpfs|devtmpfs|sysfs|proc|procfs|cgroup|cgroup2|udev|devfs|shm|none|nsfs|squashfs|fusectl|tracefs|configfs|debugfs|mqueue|pstore|securityfs|selinuxfs) continue ;; esac
		if [ "$dffstype" = "overlay" ] && [ "$dfm" != "/" ]; then continue; fi
		# Skip duplicate mounts of the same device.
		disk_key="$dfs"
		if [ -n "${seen_disk_keys[$disk_key]}" ]; then continue; fi
		seen_disk_keys[$disk_key]=1
    disk_total=$((disk_total + dft))
    disk_used=$((disk_used + dfu))
    # Escape mount point for JSON (replace backslash and double-quote)
    safe_mount=$(echo "$dfm" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ "$first_disk" -eq 1 ]; then first_disk=0; else disks_json="${disks_json},"; fi
    disks_json="${disks_json}{\"mount_point\":\"${safe_mount}\",\"used\":${dfu},\"total\":${dft}}"
	done < <(df -B1 -P -T 2>/dev/null | tail -n +2)
  disks_json="${disks_json}]"
  if [ -z "$disk_total" ]; then disk_total=0; fi
  if [ -z "$disk_used" ]; then disk_used=0; fi

  # Network (Bytes)
  # Calculate Total (Fallback)
  net_rx=$(cat /proc/net/dev 2>/dev/null | grep -v lo | awk '{sum+=$2} END {printf "%.0f", sum}')
  net_tx=$(cat /proc/net/dev 2>/dev/null | grep -v lo | awk '{sum+=$10} END {printf "%.0f", sum}')
  if [ -z "$net_rx" ]; then net_rx=0; fi
  if [ -z "$net_tx" ]; then net_tx=0; fi
  
  # Collect Per-Interface Data
  # Construct JSON array: [{"name":"eth0","rx":123,"tx":345},...]
  ifaces_json="["
  first_iface=1
  # Read /proc/net/dev line by line
  while read -r line; do
    # Skip header lines (contain |)
    if [[ "$line" == *"|"* ]]; then continue; fi
    
    # Process line using awk to extract fields (handles variable whitespace)
    # Fields: name: rx ... tx ... 
    # $1 is "name:" or "name", $2 is rx
    # awk handles the colon if attached or separate?
    # Typical: "  eth0: 123 ..." -> $1="eth0:", $2="123"
    # Or: "  eth0:123 ..." (rare)
    # Let's normalize with sed first to replace colon with space
    clean_line=$(echo "$line" | sed 's/:/ /g')
    name=$(echo "$clean_line" | awk '{print $1}')
    rx=$(echo "$clean_line" | awk '{print $2}')
    tx=$(echo "$clean_line" | awk '{print $10}')
    
    if [ -z "$name" ]; then continue; fi
    if [ -z "$rx" ]; then rx=0; fi
    if [ -z "$tx" ]; then tx=0; fi
    
    if [ "$first_iface" -eq 1 ]; then
      first_iface=0
    else
      ifaces_json="${ifaces_json},"
    fi
    ifaces_json="${ifaces_json}{\"name\":\"$name\",\"rx\":$rx,\"tx\":$tx}"
  done < /proc/net/dev
  ifaces_json="${ifaces_json}]"
  
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
  "disks": $disks_json,
  "net_rx": $net_rx,
  "net_tx": $net_tx,
  "interfaces": $ifaces_json,
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

	var host models.SSHHost
	if err := h.DB.Select("*").First(&host, data.HostID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			macAddr := "unknown"
			for _, iface := range data.Interfaces {
				if iface.Mac != "" && iface.Mac != "00:00:00:00:00:00" {
					macAddr = iface.Mac
					break
				}
			}
			recordOrphanPulse(data.HostID, c.ClientIP(), data.Hostname, macAddr)
			c.JSON(http.StatusNotFound, gin.H{
				"error":   "Host not found or has been deleted",
				"hint":    "The agent may be using an outdated configuration. Please check the service configuration on the remote host or redeploy the agent.",
				"host_id": data.HostID,
			})
		} else {
			log.Printf("Monitor Pulse: database error for host %d: %v", data.HostID, err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		}
		return
	}

	// 验证 Secret（使用时间恒定比较防止时序攻击）
	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Invalid secret"})
		return
	}

	// Successful auth -> this host is genuinely alive, so wipe any stale orphan record we may
	// have collected during a previous transient miss (e.g. a brief DB hiccup or a soft-delete
	// that was reverted).
	clearOrphanPulse(host.ID)

	// 如果监控未启用，自动启用（首次收到数据时）
	if !host.MonitorEnabled {
		host.MonitorEnabled = true
		h.DB.Model(&host).Update("monitor_enabled", true)
		log.Printf("Monitor auto-enabled for host %d (%s) on first pulse", host.ID, host.Name)
	}

	// Network traffic: serialize per host to keep lastRaw/monthly consistent
	unlockPulse := h.lockHostPulse(host.ID)
	defer unlockPulse()

	// Reload host after lock so monthly/lastRaw match DB (scheduler may have reset while waiting)
	if err := h.DB.Select(
		"id", "name", "monitor_enabled", "monitor_secret", "net_interface",
		"net_monthly_rx", "net_monthly_tx", "net_last_raw_rx", "net_last_raw_tx",
		"net_last_reset_date", "net_reset_day", "net_traffic_limit", "net_traffic_used_adjustment",
		"net_traffic_counter_mode", "last_agent_timestamp", "agent_version", "status",
		"last_pulse", "offline_at", "offline_notified", "notify_offline_enabled",
		"notify_traffic_enabled", "notify_offline_threshold", "notify_traffic_threshold",
		"traffic_alerted",
	).First(&host, data.HostID).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error"})
		return
	}

	// Strict Timestamp Check (Anti-Replay / Anti-Out-of-Order) — after reload under lock
	if data.Timestamp > 0 {
		if data.Timestamp <= host.LastAgentTimestamp {
			log.Printf("Dropped stale packet from host %d: TS %d <= Last %d", host.ID, data.Timestamp, host.LastAgentTimestamp)
			c.JSON(http.StatusOK, gin.H{"status": "ignored", "reason": "stale_timestamp"})
			return
		}
		host.LastAgentTimestamp = data.Timestamp
	}

	// 1. Billing cycle reset before delta (clears monthly + lastRaw baseline)
	dbUpdated := false
	if h.checkAndResetTraffic(&host) {
		dbUpdated = true
	}

	// 2. Counters for billing and live rates (same filter rules)
	currentRx, currentTx := monitor.ComputeTrafficTotals(host.NetInterface, data)
	data.NetRx = currentRx
	data.NetTx = currentTx

	// 3. Delta accumulation
	deltaRx, deltaTx := monitor.ComputeTrafficDelta(
		host.NetLastRawRx, host.NetLastRawTx,
		currentRx, currentTx,
		data.Uptime, host.ID,
	)

	if deltaRx > 0 || deltaTx > 0 {
		host.NetMonthlyRx += deltaRx
		host.NetMonthlyTx += deltaTx
		dbUpdated = true

		// Check Traffic Threshold
		if host.NetTrafficLimit > 0 {
			measured := monitor.BillableTraffic(host.NetTrafficCounterMode, host.NetMonthlyRx, host.NetMonthlyTx)

			totalUsed := measured + host.NetTrafficUsedAdjustment
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

				utils.SendNotification(h.DB, host, fmt.Sprintf("Traffic Warning: %s", host.Name), msg, h.Config.Security.EncryptionKey)
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

		// Check if this was a short outage (< 1 minute) — suppress notifications
		wasShortOutage := host.OfflineAt != nil && time.Since(*host.OfflineAt) < 1*time.Minute

		// Reset offline tracking fields
		host.OfflineAt = nil
		host.OfflineNotified = false

		// Record "Coming Online" event
		go func(hostID uint) {
			h.DB.Create(&models.MonitorStatusLog{
				HostID:    hostID,
				Status:    "online",
				CreatedAt: time.Now(),
			})
		}(host.ID)

		// Send Back Online Notification (only if it was a real outage, not a short blip)
		if host.NotifyOfflineEnabled && !wasShortOutage {
			utils.SendNotification(h.DB, host,
				fmt.Sprintf("Host Back Online: %s", host.Name),
				fmt.Sprintf("Host '%s' (ID: %d) is back online.", host.Name, host.ID),
				h.Config.Security.EncryptionKey,
			)
		}

		if wasShortOutage {
			log.Printf("Monitor: Host %s (ID: %d) recovered from short outage, notifications suppressed", host.Name, host.ID)
		}

		dbUpdated = true
	}

	if dbUpdated {
		updateFields := map[string]interface{}{
			"monitor_enabled":      host.MonitorEnabled,
			"net_last_raw_rx":      host.NetLastRawRx,
			"net_last_raw_tx":      host.NetLastRawTx,
			"net_last_reset_date":  host.NetLastResetDate,
			"traffic_alerted":      host.TrafficAlerted,
			"agent_version":        host.AgentVersion,
			"status":               host.Status,
			"last_pulse":           host.LastPulse,
			"last_agent_timestamp": host.LastAgentTimestamp,
			"offline_at":           host.OfflineAt,
			"offline_notified":     host.OfflineNotified,
		}

		// Use atomic SQL increments for traffic counters to avoid race condition
		// between concurrent pulse handlers from the same host
		if deltaRx > 0 || deltaTx > 0 {
			updateFields["net_monthly_rx"] = gorm.Expr("net_monthly_rx + ?", deltaRx)
			updateFields["net_monthly_tx"] = gorm.Expr("net_monthly_tx + ?", deltaTx)
		} else {
			updateFields["net_monthly_rx"] = host.NetMonthlyRx
			updateFields["net_monthly_tx"] = host.NetMonthlyTx
		}

		h.DB.Model(&models.SSHHost{}).Where("id = ?", host.ID).Updates(updateFields)
	}

	var trafficRow struct {
		NetMonthlyRx uint64
		NetMonthlyTx uint64
	}
	if err := h.DB.Model(&models.SSHHost{}).Where("id = ?", host.ID).
		Select("net_monthly_rx", "net_monthly_tx").First(&trafficRow).Error; err == nil {
		data.NetMonthlyRx = trafficRow.NetMonthlyRx
		data.NetMonthlyTx = trafficRow.NetMonthlyTx
	} else {
		data.NetMonthlyRx = host.NetMonthlyRx
		data.NetMonthlyTx = host.NetMonthlyTx
	}
	// Pass Config to Frontend
	data.NetTrafficLimit = host.NetTrafficLimit
	data.NetTrafficUsedAdjustment = host.NetTrafficUsedAdjustment
	data.NetTrafficCounterMode = host.NetTrafficCounterMode

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
		go func(d monitor.MetricData, db *gorm.DB) {
			monitorRecordSem <- struct{}{}
			defer func() { <-monitorRecordSem }()
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
			db.Create(&record)
		}(data, h.DB)
	}

	c.Status(http.StatusOK)
}

// AgentEvent receives status updates or events from the agent
func (h *MonitorHandler) AgentEvent(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	secret := authHeader[7:]

	var event monitor.AgentEvent
	if err := c.ShouldBindJSON(&event); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	host, err := lookupPulseHost(h.DB, event.HostID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
		return
	}

	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		c.JSON(http.StatusForbidden, gin.H{"error": "Invalid secret"})
		return
	}

	monitor.GlobalHub.AgentEvent(event)
	c.Status(http.StatusOK)
}

// Stream WebSocket for Dashboard
// Authentication: Uses one-time ticket (from query param "token") or falls back to
// Authorization header / access_token cookie. This handler is NOT behind AuthMiddleware
// because WebSocket connections cannot set custom HTTP headers cross-origin.
// Security: Ticket is one-time use and short-lived; broadcasts are scoped per user (admin sees all).
func (h *MonitorHandler) Stream(c *gin.Context) {
	userID, role, ok := authenticateMonitorStream(c, h.Config.Security.JWTSecret, h.DB)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "invalid or expired ticket",
		})
		return
	}

	allowed, isAdmin := monitorAllowedHostIDs(h.DB, userID, role)

	upgrader := createUpgrader(h.Config.Server.AllowedOrigins, h.Config.Server.Mode == "debug")

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	monitor.GlobalHub.Register(conn, allowed, isAdmin)

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
	c.ShouldBindJSON(&req)

	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
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

	// FIX: Handle IPv6 in Server URL
	hostHeader := c.Request.Host
	// If it contains colons but no brackets, and it's not just a port (which shouldn't happen for Host header),
	// wrap it. simpler: if it looks like a raw IPv6, wrap it.
	// But c.Request.Host usually includes port.
	// If [::1]:8080 -> OK.
	// If ::1 -> needs brackets.
	// If 127.0.0.1:8080 -> OK.
	// Safe bet: if it has colons and no brackets, checking if it is a valid IP might be overkill but safe.
	// Let's just fix the SSH dial first, which is the most likely failure point.
	// For ServerURL, let's just ensure we don't break existing ones.
	// Actually, if the user visits via IPv6, the browser sends Host: [::1]:8080.
	serverURL := fmt.Sprintf("%s://%s", scheme, hostHeader)

	client, newFp, err := openMonitorSSH(host, h.Config.Security.EncryptionKey, req.Insecure)
	if err != nil {
		log.Printf("Monitor Deploy: SSH Dial failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("SSH Connection failed: %v", err)})
		return
	}
	if newFp != "" && host.Fingerprint == "" {
		host.Fingerprint = newFp
		h.DB.Model(host).Update("fingerprint", newFp)
	}
	stopCancelWatch := closeSSHClientWhenRequestDone(c.Request, client)
	defer stopCancelWatch()
	defer client.Close()

	password, _ := decryptHostCredentials(host, h.Config.Security.EncryptionKey)

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
		stopCmd = "sudo -S sh -c 'systemctl stop termiscope-agent || true'"
		session.Stdin = strings.NewReader(password + "\n")
	}
	// We ignore errors here because the service might not exist yet
	session.Run(stopCmd)
	session.Close()

	// 2. Setup Directory
	session, _ = client.NewSession()
	setupScript := `
for dir in "/opt" "/usr/local" "/var/lib" "/tmp"; do
	if mkdir -p "$dir/termiscope/agent" 2>/dev/null && touch "$dir/termiscope/agent/.test" 2>/dev/null; then
		rm -f "$dir/termiscope/agent/.test"
		echo "$dir/termiscope/agent"
		exit 0
	fi
done
exit 1
`
	setupCmd := fmt.Sprintf("sh -c '%s'", setupScript)
	if host.Username != "root" {
		setupCmd = fmt.Sprintf("sudo -S sh -c '%s'", setupScript)
		session.Stdin = strings.NewReader(password + "\n")
	}
	out, err := session.CombinedOutput(setupCmd)
	if err != nil {
		log.Printf("Monitor Deploy: Setup dir failed: %v, Out: %s", err, string(out))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to find writable directory: " + string(out)})
		return
	}
	installDir := strings.TrimSpace(string(out))
	if installDir == "" {
		installDir = "/opt/termiscope/agent"
	}
	session.Close()

	// 3. Upload Binary
	remoteBinaryPath := fmt.Sprintf("%s/termiscope-agent", installDir)
	uploadPath := remoteBinaryPath
	if host.Username != "root" {
		// Use unique temp file to avoid permission issues if specific file exists owned by root
		uploadPath = fmt.Sprintf("/tmp/termiscope-agent-%d", time.Now().UnixNano())
	}

	session, _ = client.NewSession()
	var stderrBuf bytes.Buffer
	session.Stderr = &stderrBuf

	w, _ := session.StdinPipe()
	go func() {
		if w != nil {
			w.Write(binaryContent)
			w.Close()
		}
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
		moveCmd := fmt.Sprintf("sudo -S mv %s %s", uploadPath, remoteBinaryPath)
		session.Stdin = strings.NewReader(password + "\n")
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
		chmodCmd = fmt.Sprintf("sudo -S chmod +x %s", remoteBinaryPath)
		session.Stdin = strings.NewReader(password + "\n")
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

	configPath := fmt.Sprintf("%s/agent.json", installDir)
	agentConfig := gin.H{
		"server_url": serverURL,
		"secret":     secret,
		"host_id":    host.ID,
		"interval":   "10s",
		"insecure":   req.Insecure,
	}
	configBytes, _ := json.Marshal(agentConfig)
	session, _ = client.NewSession()
	w, _ = session.StdinPipe()
	go func() {
		if w != nil {
			w.Write(configBytes)
			w.Close()
		}
	}()
	configTarget := configPath
	if host.Username != "root" {
		configTarget = "/tmp/termiscope-agent.json"
	}
	if err := session.Run(fmt.Sprintf("cat > %s", configTarget)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to write agent config"})
		return
	}
	session.Close()
	if host.Username != "root" {
		session, _ = client.NewSession()
		session.Stdin = strings.NewReader(password + "\n")
		installConfigCmd := fmt.Sprintf("sudo -S sh -c 'mv %s %s && chmod 600 %s'",
			utils.ShellEscape(configTarget), utils.ShellEscape(configPath), utils.ShellEscape(configPath))
		if out, err := session.CombinedOutput(installConfigCmd); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to install agent config: " + string(out)})
			return
		}
		session.Close()
	} else {
		session, _ = client.NewSession()
		_ = session.Run(fmt.Sprintf("chmod 600 %s", configPath))
		session.Close()
	}

	// 4. Create Service based on init system
	execCmd := fmt.Sprintf("%s -config %s", remoteBinaryPath, configPath)

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
WorkingDirectory=%s

[Install]
WantedBy=multi-user.target
`, execCmd, installDir)

		session, _ = client.NewSession()
		var serviceReader bytes.Buffer
		serviceReader.WriteString(serviceContent)

		w, _ := session.StdinPipe()
		go func() {
			if w != nil {
				w.Write(serviceReader.Bytes())
				w.Close()
			}
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
			session.Stdin = strings.NewReader(password + "\n")
			session.Run("sudo -S mv /tmp/termiscope-agent.service /etc/systemd/system/termiscope-agent.service")
			session.Close()
		}

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "systemctl daemon-reload && systemctl enable --now termiscope-agent"
		if host.Username != "root" {
			cmd = "sudo -S sh -c '" + cmd + "'"
			session.Stdin = strings.NewReader(password + "\n")
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

		w, _ := session.StdinPipe()
		go func() {
			if w != nil {
				w.Write(initReader.Bytes())
				w.Close()
			}
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

		w, _ := session.StdinPipe()
		go func() {
			if w != nil {
				w.Write(upstartReader.Bytes())
				w.Close()
			}
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
			session.Stdin = strings.NewReader(password + "\n")
			session.Run("sudo -S mv /tmp/termiscope-agent.conf /etc/init/termiscope-agent.conf")
			session.Close()
		}

		// Start service
		session, _ = client.NewSession()
		cmd := "initctl reload-configuration && initctl start termiscope-agent"
		if host.Username != "root" {
			cmd = "sudo -S sh -c '" + cmd + "'"
			session.Stdin = strings.NewReader(password + "\n")
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

		w, _ := session.StdinPipe()
		go func() {
			if w != nil {
				w.Write(rcReader.Bytes())
				w.Close()
			}
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

		w, _ := session.StdinPipe()
		go func() {
			if w != nil {
				w.Write(sysvReader.Bytes())
				w.Close()
			}
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
			session.Stdin = strings.NewReader(password + "\n")
			session.Run("sudo -S mv /tmp/termiscope-agent /etc/init.d/termiscope-agent")
			session.Close()
		}

		// Enable and Start
		session, _ = client.NewSession()
		cmd := "chmod +x /etc/init.d/termiscope-agent && "
		// Try chkconfig first (CentOS/RHEL), then update-rc.d (Debian/Ubuntu)
		cmd += "(chkconfig --add termiscope-agent && chkconfig termiscope-agent on || update-rc.d termiscope-agent defaults) && "
		cmd += "/etc/init.d/termiscope-agent start"
		if host.Username != "root" {
			cmd = "sudo -S sh -c '" + cmd + "'"
			session.Stdin = strings.NewReader(password + "\n")
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
	id := c.Param("id")
	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	// Notify clients to remove immediately
	monitor.GlobalHub.RemoveHost(host.ID)
	// Update DB immediately
	h.DB.Model(&host).Update("monitor_enabled", false)

	password, _ := decryptHostCredentials(host, h.Config.Security.EncryptionKey)

	client, _, err := openMonitorSSH(host, h.Config.Security.EncryptionKey, false)
	if err != nil {
		log.Printf("Monitor Stop: SSH Dial failed: %v", err)
		c.JSON(http.StatusOK, gin.H{"message": "Monitoring disabled (Agent stop failed: SSH connection error)"})
		return
	}
	defer client.Close()

	session, _ := client.NewSession()
	defer session.Close()

	cmd := "systemctl disable --now termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload && rm -rf /opt/termiscope/agent"
	if host.Username != "root" {
		cmd = "sudo -S sh -c '" + cmd + "'"
		session.Stdin = strings.NewReader(password + "\n")
	}

	if err := session.Run(cmd); err != nil {
		log.Printf("Monitor Stop: Failed to run cleanup commands: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Monitoring stopped and agent removed"})
}

// GetHostTrafficHistory returns derived Rx/Tx rates from monitor_records for charts.
func (h *MonitorHandler) GetHostTrafficHistory(c *gin.Context) {
	id := c.Param("id")
	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	rangeStr := c.DefaultQuery("range", "24h")
	duration, err := database.ParseNetworkStatsRange(rangeStr)
	if err != nil {
		duration = 24 * time.Hour
	}

	points, err := database.QueryHostTrafficHistory(h.DB, host.ID, time.Now().Add(-duration))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch traffic history"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"points": points, "range": rangeStr})
}

// GetStatusLogs returns the status history for a host
func (h *MonitorHandler) GetStatusLogs(c *gin.Context) {
	id := c.Param("id")
	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	page := utils.GetIntQuery(c, "page", 1)
	pageSize := utils.GetIntQuery(c, "page_size", 20)
	offset := (page - 1) * pageSize

	var logs []models.MonitorStatusLog
	var total int64

	db := h.DB.Model(&models.MonitorStatusLog{}).Where("host_id = ?", host.ID)

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

// GetTrafficResetLogs returns the traffic reset history logs.
// If host_id is provided, filter by host; otherwise return all.
func (h *MonitorHandler) GetTrafficResetLogs(c *gin.Context) {
	page := utils.GetIntQuery(c, "page", 1)
	pageSize := utils.GetIntQuery(c, "page_size", 20)
	offset := (page - 1) * pageSize
	hostId := c.Query("host_id")

	var logs []models.MonitorTrafficResetLog
	var total int64

	db := h.DB.Model(&models.MonitorTrafficResetLog{})
	if hostId != "" {
		if _, ok := loadSSHHostForUser(h.DB, hostId, c); !ok {
			denyHostAccess(c)
			return
		}
		db = db.Where("host_id = ?", hostId)
	} else if middleware.GetRole(c) != "admin" {
		var ids []uint
		h.DB.Model(&models.SSHHost{}).Where("user_id = ?", middleware.GetUserID(c)).Pluck("id", &ids)
		if len(ids) == 0 {
			c.JSON(http.StatusOK, gin.H{"data": []interface{}{}, "total": 0, "page": page})
			return
		}
		db = db.Where("host_id IN ?", ids)
	}

	db.Count(&total)

	if err := db.Order("created_at desc").Offset(offset).Limit(pageSize).Find(&logs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch traffic reset logs"})
		return
	}

	type LogWithHost struct {
		models.MonitorTrafficResetLog
		HostName string `json:"host_name"`
	}

	hostNames := make(map[uint]string)
	if len(logs) > 0 {
		ids := make([]uint, 0, len(logs))
		seen := make(map[uint]bool)
		for _, l := range logs {
			if !seen[l.HostID] {
				seen[l.HostID] = true
				ids = append(ids, l.HostID)
			}
		}
		var hosts []models.SSHHost
		if err := h.DB.Select("id", "name").Where("id IN ?", ids).Find(&hosts).Error; err == nil {
			for _, hst := range hosts {
				hostNames[hst.ID] = hst.Name
			}
		}
	}

	enrichedLogs := make([]LogWithHost, 0, len(logs))
	for _, l := range logs {
		enrichedLogs = append(enrichedLogs, LogWithHost{
			MonitorTrafficResetLog: l,
			HostName:               hostNames[l.HostID],
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"data":  enrichedLogs,
		"total": total,
		"page":  page,
	})
}

// GetTrafficResetDebug returns diagnostic info for a host's traffic reset state.
func (h *MonitorHandler) GetTrafficResetDebug(c *gin.Context) {
	id := c.Param("id")
	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	now := time.Now()
	cycleStartStr := getCycleStartDate(now, host.NetResetDay)

	shouldReset := false
	reason := "net_last_reset_date >= currentCycleStart (already reset for this cycle)"
	if host.NetLastResetDate == "" {
		shouldReset = true
		reason = "net_last_reset_date is empty"
	} else if host.NetLastResetDate < cycleStartStr {
		shouldReset = true
		reason = fmt.Sprintf("net_last_reset_date '%s' < currentCycleStart '%s'", host.NetLastResetDate, cycleStartStr)
	}

	var logCount int64
	h.DB.Model(&models.MonitorTrafficResetLog{}).
		Where("host_id = ? AND reset_date = ? AND status = 'success'", host.ID, cycleStartStr).
		Count(&logCount)

	c.JSON(http.StatusOK, gin.H{
		"host_id":             host.ID,
		"host_name":           host.Name,
		"net_reset_day":       host.NetResetDay,
		"net_last_reset_date": host.NetLastResetDate,
		"net_monthly_rx":      host.NetMonthlyRx,
		"net_monthly_tx":      host.NetMonthlyTx,
		"current_cycle_start": cycleStartStr,
		"should_reset":        shouldReset,
		"reason":              reason,
		"existing_log_count":  logCount,
		"server_time":         now.Format("2006-01-02 15:04:05"),
		"server_timezone":     now.Location().String(),
	})
}

// ForceTrafficReset forces a traffic reset for a specific host.
func (h *MonitorHandler) ForceTrafficReset(c *gin.Context) {
	id := c.Param("id")
	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	cycleStartStr := getCycleStartDate(time.Now(), host.NetResetDay)

	// Force reset: clear traffic and update date
	err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&host).Updates(map[string]interface{}{
			"net_monthly_rx":              0,
			"net_monthly_tx":              0,
			"net_traffic_used_adjustment": 0,
			"net_last_raw_rx":             0,
			"net_last_raw_tx":             0,
			"net_last_reset_date":         cycleStartStr,
			"traffic_alerted":             false,
		}).Error; err != nil {
			return err
		}

		if err := tx.Create(&models.MonitorTrafficResetLog{
			HostID:    host.ID,
			ResetDate: cycleStartStr,
			Status:    "success",
			CreatedAt: time.Now(),
		}).Error; err != nil {
			return err
		}
		return nil
	})

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Force reset failed: %v", err)})
		return
	}

	log.Printf("Force Traffic Reset SUCCESS for Host %d (%s): Cycle %s", host.ID, host.Name, cycleStartStr)
	c.JSON(http.StatusOK, gin.H{
		"message":    "Traffic reset forced successfully",
		"cycle_date": cycleStartStr,
	})
}

func closeSSHClientWhenRequestDone(request *http.Request, client interface{ Close() error }) func() {
	if request == nil {
		return func() {}
	}

	done := make(chan struct{})
	var once sync.Once
	go func() {
		select {
		case <-request.Context().Done():
			_ = client.Close()
		case <-done:
		}
	}()

	return func() {
		once.Do(func() {
			close(done)
		})
	}
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

	// Set headers for streaming
	c.Header("Content-Type", "application/x-ndjson")
	c.Header("Transfer-Encoding", "chunked")
	c.Header("X-Content-Type-Options", "nosniff")

	// Flush headers immediately
	c.Writer.Flush()

	ctx := c.Request.Context()

	// 并发部署(限制并发数避免资源耗尽)
	maxConcurrent := 20
	semaphore := make(chan struct{}, maxConcurrent)
	var wg sync.WaitGroup

	// Channel to collect results for streaming
	resultChan := make(chan BatchDeployResult)

	// Start result streamer
	go func() {
		encoder := json.NewEncoder(c.Writer)
		for {
			select {
			case <-ctx.Done():
				return
			case res, ok := <-resultChan:
				if !ok {
					return
				}
				if err := encoder.Encode(res); err != nil {
					return
				}
				c.Writer.Flush()
			}
		}
	}()

	sendResult := func(res BatchDeployResult) bool {
		select {
		case resultChan <- res:
			return true
		case <-ctx.Done():
			return false
		}
	}

deployLoop:
	for _, hostID := range req.HostIDs {
		select {
		case <-ctx.Done():
			break deployLoop
		default:
		}
		wg.Add(1)
		go func(id uint) {
			defer wg.Done()
			select {
			case semaphore <- struct{}{}: // 获取信号量
			case <-ctx.Done():
				return
			}
			defer func() { <-semaphore }() // 释放信号量

			result := BatchDeployResult{HostID: id}

			host, ok := loadSSHHostForUserUint(h.DB, id, c)
			if !ok {
				result.Success = false
				result.Message = "主机不存在或无权访问"
				sendResult(result)
				return
			}

			result.HostName = host.Name

			select {
			case <-ctx.Done():
				return
			default:
			}

			// 执行部署
			err := h.deployToHost(host, req.Insecure, c.Request)
			if err != nil {
				result.Success = false
				result.Message = err.Error()
			} else {
				result.Success = true
				result.Message = "部署成功"
			}

			sendResult(result)
		}(hostID)
	}

	wg.Wait()
	close(resultChan)
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

	password, _ := decryptHostCredentials(host, h.Config.Security.EncryptionKey)

	client, newFp, err := openMonitorSSH(host, h.Config.Security.EncryptionKey, insecure)
	if err != nil {
		return fmt.Errorf("SSH连接失败: %v", err)
	}
	if newFp != "" && host.Fingerprint == "" {
		h.DB.Model(host).Update("fingerprint", newFp)
	}
	stopCancelWatch := closeSSHClientWhenRequestDone(request, client)
	defer stopCancelWatch()
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
		stopCmd = "sudo -S sh -c 'systemctl stop termiscope-agent || true'"
		session.Stdin = strings.NewReader(password + "\n")
	}
	session.Run(stopCmd)
	session.Close()

	// Setup Directory
	session, _ = client.NewSession()
	setupScript := `
for dir in "/opt" "/usr/local" "/var/lib" "/tmp"; do
	if mkdir -p "$dir/termiscope/agent" 2>/dev/null && touch "$dir/termiscope/agent/.test" 2>/dev/null; then
		rm -f "$dir/termiscope/agent/.test"
		echo "$dir/termiscope/agent"
		exit 0
	fi
done
exit 1
`
	setupCmd := fmt.Sprintf("sh -c '%s'", setupScript)
	if host.Username != "root" {
		setupCmd = fmt.Sprintf("sudo -S sh -c '%s'", setupScript)
		session.Stdin = strings.NewReader(password + "\n")
	}
	out, err := session.CombinedOutput(setupCmd)
	if err != nil {
		return fmt.Errorf("创建目录失败: %s", string(out))
	}
	installDir := strings.TrimSpace(string(out))
	if installDir == "" {
		installDir = "/opt/termiscope/agent"
	}
	session.Close()

	// Upload Binary
	remoteBinaryPath := fmt.Sprintf("%s/termiscope-agent", installDir)
	uploadPath := remoteBinaryPath
	if host.Username != "root" {
		uploadPath = fmt.Sprintf("/tmp/termiscope-agent-%d", time.Now().UnixNano())
	}

	session, _ = client.NewSession()
	w, _ := session.StdinPipe()
	go func() {
		if w != nil {
			w.Write(binaryContent)
			w.Close()
		}
	}()

	if err := session.Run(fmt.Sprintf("cat > %s", uploadPath)); err != nil {
		return fmt.Errorf("上传agent失败")
	}
	session.Close()

	// Move and Chmod
	if host.Username != "root" {
		session, _ = client.NewSession()
		moveCmd := fmt.Sprintf("sudo -S mv %s %s", uploadPath, remoteBinaryPath)
		session.Stdin = strings.NewReader(password + "\n")
		if out, err := session.CombinedOutput(moveCmd); err != nil {
			return fmt.Errorf("移动文件失败: %s", string(out))
		}
		session.Close()
	}

	session, _ = client.NewSession()
	chmodCmd := fmt.Sprintf("chmod +x %s", remoteBinaryPath)
	if host.Username != "root" {
		chmodCmd = fmt.Sprintf("sudo -S chmod +x %s", remoteBinaryPath)
		session.Stdin = strings.NewReader(password + "\n")
	}
	if out, err := session.CombinedOutput(chmodCmd); err != nil {
		return fmt.Errorf("设置权限失败: %s", string(out))
	}
	session.Close()

	configPath := fmt.Sprintf("%s/agent.json", installDir)
	agentConfig := gin.H{
		"server_url": serverURL,
		"secret":     secret,
		"host_id":    host.ID,
		"interval":   "10s",
		"insecure":   insecure,
	}
	configBytes, _ := json.Marshal(agentConfig)
	session, _ = client.NewSession()
	w, _ = session.StdinPipe()
	go func() {
		if w != nil {
			w.Write(configBytes)
			w.Close()
		}
	}()
	configTarget := configPath
	if host.Username != "root" {
		configTarget = "/tmp/termiscope-agent.json"
	}
	if err := session.Run(fmt.Sprintf("cat > %s", configTarget)); err != nil {
		return fmt.Errorf("写入 agent 配置失败")
	}
	session.Close()
	if host.Username != "root" {
		session, _ = client.NewSession()
		session.Stdin = strings.NewReader(password + "\n")
		installConfigCmd := fmt.Sprintf("sudo -S sh -c 'mv %s %s && chmod 600 %s'",
			utils.ShellEscape(configTarget), utils.ShellEscape(configPath), utils.ShellEscape(configPath))
		if out, err := session.CombinedOutput(installConfigCmd); err != nil {
			return fmt.Errorf("安装 agent 配置失败: %s", string(out))
		}
		session.Close()
	} else {
		session, _ = client.NewSession()
		_ = session.Run(fmt.Sprintf("chmod 600 %s", configPath))
		session.Close()
	}

	// Create Systemd Service
	execCmd := fmt.Sprintf("%s -config %s", remoteBinaryPath, configPath)

	serviceContent := fmt.Sprintf(`[Unit]
Description=TermiScope Monitor Agent
After=network.target

[Service]
ExecStart=%s
Restart=always
User=root
WorkingDirectory=%s

[Install]
WantedBy=multi-user.target
`, execCmd, installDir)

	session, _ = client.NewSession()
	var serviceReader bytes.Buffer
	serviceReader.WriteString(serviceContent)

	w, _ = session.StdinPipe()
	go func() {
		if w != nil {
			w.Write(serviceReader.Bytes())
			w.Close()
		}
	}()

	targetPath := "/etc/systemd/system/termiscope-agent.service"
	if host.Username != "root" {
		targetPath = "/tmp/termiscope-agent.service"
	}

	session.Run(fmt.Sprintf("cat > %s", targetPath))
	session.Close()

	if host.Username != "root" && targetPath == "/tmp/termiscope-agent.service" {
		session, _ := client.NewSession()
		session.Stdin = strings.NewReader(password + "\n")
		session.Run("sudo -S mv /tmp/termiscope-agent.service /etc/systemd/system/termiscope-agent.service")
		session.Close()
	}

	// Enable and Start
	session, _ = client.NewSession()
	cmd := "systemctl daemon-reload && systemctl enable --now termiscope-agent"
	if host.Username != "root" {
		cmd = "sudo -S sh -c '" + cmd + "'"
		session.Stdin = strings.NewReader(password + "\n")
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

	// Set headers for streaming
	c.Header("Content-Type", "application/x-ndjson")
	c.Header("Transfer-Encoding", "chunked")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Writer.Flush()

	// 并发停止(限制并发数)
	maxConcurrent := 20
	semaphore := make(chan struct{}, maxConcurrent)
	var wg sync.WaitGroup

	resultChan := make(chan BatchStopResult)

	// Streamer
	go func() {
		encoder := json.NewEncoder(c.Writer)
		for res := range resultChan {
			encoder.Encode(res)
			c.Writer.Flush()
		}
	}()

	for _, hostID := range req.HostIDs {
		wg.Add(1)
		go func(id uint) {
			defer wg.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			result := BatchStopResult{HostID: id}

			host, ok := loadSSHHostForUserUint(h.DB, id, c)
			if !ok {
				result.Success = false
				result.Message = "主机不存在或无权访问"
				resultChan <- result
				return
			}

			result.HostName = host.Name

			// 执行停止
			err := h.stopMonitorOnHost(host)
			if err != nil {
				result.Success = false
				result.Message = err.Error()
			} else {
				result.Success = true
				result.Message = "停止成功"
			}

			resultChan <- result
		}(hostID)
	}

	wg.Wait()
	close(resultChan)
}

// stopMonitorOnHost - 停止指定主机的监控(从Stop函数提取的核心逻辑)
func (h *MonitorHandler) stopMonitorOnHost(host *models.SSHHost) error {
	// Update DB first
	h.DB.Model(host).Update("monitor_enabled", false)

	password, _ := decryptHostCredentials(host, h.Config.Security.EncryptionKey)

	client, _, err := openMonitorSSH(host, h.Config.Security.EncryptionKey, false)
	if err != nil {
		log.Printf("Monitor BatchStop: SSH连接失败(已更新DB): %v", err)
		return nil
	}
	defer client.Close()

	// Stop and disable service
	session, _ := client.NewSession()
	cmd := "systemctl stop termiscope-agent && systemctl disable termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload"
	if host.Username != "root" {
		cmd = "sudo -S sh -c '" + cmd + "'"
		session.Stdin = strings.NewReader(password + "\n")
	}

	session.Run(cmd)
	session.Close()

	return nil
}

// GetInstallScript 生成一键安装脚本
func (h *MonitorHandler) GetInstallScript(c *gin.Context) {
	hostID := c.Query("host_id")
	secret := extractMonitorSecret(c)
	osType := c.Query("os") // "windows" or empty (linux)

	if hostID == "" || secret == "" {
		if osType == "windows" {
			c.String(http.StatusBadRequest, "Write-Error 'host_id and Authorization Bearer secret are required'")
		} else {
			c.String(http.StatusBadRequest, "#!/bin/bash\necho 'Error: host_id and Authorization Bearer secret required'\nexit 1")
		}
		return
	}

	host, err := verifyMonitorSecret(h.DB, hostID, secret)
	if err != nil {
		if osType == "windows" {
			c.String(http.StatusForbidden, "Write-Error 'Invalid host or secret'")
		} else {
			c.String(http.StatusForbidden, "#!/bin/bash\necho 'Error: Invalid host or secret'\nexit 1")
		}
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
	var tmplFile string
	if osType == "windows" {
		tmplFile = "scripts/install_agent.ps1.tmpl"
	} else {
		tmplFile = "scripts/install_agent.sh.tmpl"
	}

	// 读取模板文件
	tmplContent, err := ioutil.ReadFile(tmplFile)
	if err != nil {
		log.Printf("Failed to read install script template: %v", err)
		if osType == "windows" {
			c.String(http.StatusInternalServerError, "Write-Error 'Failed to read installation template'")
		} else {
			c.String(http.StatusInternalServerError, "#!/bin/bash\necho 'Error: Failed to read installation template'\nexit 1")
		}
		return
	}

	script := string(tmplContent)
	script = strings.ReplaceAll(script, "{{HOST_NAME}}", host.Name)
	script = strings.ReplaceAll(script, "{{HOST_ID}}", hostID)
	script = strings.ReplaceAll(script, "{{SERVER_URL}}", serverURL)
	script = strings.ReplaceAll(script, "{{SECRET}}", secret)

	// 强制转换 CRLF 为 LF，解决 Windows/Linux 换行符兼容性问题
	// For Windows PowerShell, CRLF is fine, but LF is also fine.
	if osType != "windows" {
		script = strings.ReplaceAll(script, "\r\n", "\n")
	}

	c.Header("Content-Type", "text/plain; charset=utf-8")
	c.String(http.StatusOK, script)
}

// GetUninstallScript 生成卸载脚本
func (h *MonitorHandler) GetUninstallScript(c *gin.Context) {
	secret := extractMonitorSecret(c)
	hostID := c.Query("host_id")

	if hostID == "" || secret == "" {
		c.String(http.StatusBadRequest, "#!/bin/bash\necho 'Error: host_id and secret required'\nexit 1")
		return
	}
	if _, err := verifyMonitorSecret(h.DB, hostID, secret); err != nil {
		c.String(http.StatusForbidden, "#!/bin/bash\necho 'Error: Invalid host or secret'\nexit 1")
		return
	}

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
	secret := extractMonitorSecret(c)
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

	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		c.JSON(http.StatusForbidden, gin.H{"error": "invalid secret"})
		return
	}

	// 更新状态为未启用监控
	h.DB.Model(&host).Update("monitor_enabled", false)
	c.JSON(http.StatusOK, gin.H{"success": true})
}

type agentManifestResponse struct {
	Version   string `json:"version"`
	Filename  string `json:"filename"`
	SHA256    string `json:"sha256"`
	Size      int64  `json:"size"`
	Signature string `json:"signature"`
}

func (h *MonitorHandler) GetAgentManifest(c *gin.Context) {
	host, err := h.authenticateAgentRequest(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	goos := strings.ToLower(strings.TrimSpace(c.Query("os")))
	goarch := strings.ToLower(strings.TrimSpace(c.Query("arch")))
	if goos == "" || goarch == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "os and arch parameters are required"})
		return
	}

	filename, err := resolveAgentFilename(goos, goarch)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	filePath := filepath.Join("agents", filename)

	// Read from cache
	hashInfo, err := utils.GetAgentHashInfo(filename)

	if err != nil {
		log.Printf("Agent manifest failed for %s: %v (cache and regeneration failed)", filename, err)

		// Fallback to on-the-fly calculation if cache fails completely
		shaValue, fileSize, compErr := computeFileSHA256(filePath)
		if compErr != nil {
			log.Printf("Agent file not found or cannot be hashed: %s: %v", filePath, compErr)
			c.JSON(http.StatusNotFound, gin.H{"error": "Agent binary not found"})
			return
		}
		hashInfo = &utils.AgentHashInfo{
			SHA256: shaValue,
			Size:   fileSize,
		}
	}

	shaValue := hashInfo.SHA256
	fileSize := hashInfo.Size

	version := strings.TrimSpace(config.Version)
	if agentVersion, ok := utils.AgentBinaryVersion(filePath); ok {
		version = agentVersion
	}
	if version == "" {
		version = "dev"
	}

	manifest := agentManifestResponse{
		Version:   version,
		Filename:  filename,
		SHA256:    shaValue,
		Size:      fileSize,
		Signature: signAgentManifest(host.MonitorSecret, version, filename, shaValue, fileSize),
	}

	c.JSON(http.StatusOK, manifest)
}

// DownloadAgent 提供 agent 二进制文件下载
func (h *MonitorHandler) DownloadAgent(c *gin.Context) {
	filename := c.Param("filename")
	if _, err := h.authenticateAgentRequest(c); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// 验证文件名，防止路径遍历攻击
	if strings.Contains(filename, "..") || strings.Contains(filename, "/") || strings.Contains(filename, "\\") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid filename"})
		return
	}

	// 构建文件路径
	filePath := fmt.Sprintf("agents/%s", filename)

	// 检查文件是否存在（使用 Stat 避免将大文件读入内存）
	if info, err := os.Stat(filePath); err != nil {
		if os.IsNotExist(err) {
			log.Printf("Agent file not found: %s", filePath)
			c.JSON(http.StatusNotFound, gin.H{"error": "Agent binary not found"})
			return
		}
		log.Printf("Agent file stat failed: %s: %v", filePath, err)
		c.JSON(http.StatusNotFound, gin.H{"error": "Agent binary not found"})
		return
	} else if info.IsDir() {
		log.Printf("Agent file path is a directory: %s", filePath)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid agent binary"})
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

func (h *MonitorHandler) authenticateAgentRequest(c *gin.Context) (*models.SSHHost, error) {
	hostIDStr := strings.TrimSpace(c.Query("host_id"))
	if hostIDStr == "" {
		return nil, fmt.Errorf("host_id parameter is required")
	}

	hostID, err := strconv.ParseUint(hostIDStr, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid host_id")
	}

	host, err := lookupPulseHost(h.DB, uint(hostID))
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("host not found")
		}
		return nil, fmt.Errorf("failed to load host")
	}

	secret := ""
	authHeader := c.GetHeader("Authorization")
	if len(authHeader) >= 7 && strings.EqualFold(authHeader[:7], "Bearer ") {
		secret = strings.TrimSpace(authHeader[7:])
	}

	if secret == "" {
		return nil, fmt.Errorf("authorization required")
	}

	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		return nil, fmt.Errorf("invalid secret")
	}

	return host, nil
}

func resolveAgentFilename(goos, goarch string) (string, error) {
	switch goos {
	case "linux":
		switch goarch {
		case "amd64", "arm64", "arm":
			return fmt.Sprintf("termiscope-agent-linux-%s", goarch), nil
		}
	case "darwin":
		switch goarch {
		case "amd64", "arm64":
			return fmt.Sprintf("termiscope-agent-darwin-%s", goarch), nil
		}
	case "windows":
		switch goarch {
		case "amd64", "arm64":
			return fmt.Sprintf("termiscope-agent-windows-%s.exe", goarch), nil
		}
	}

	return "", fmt.Errorf("unsupported platform: %s/%s", goos, goarch)
}

func computeFileSHA256(filePath string) (string, int64, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", 0, err
	}
	defer file.Close()

	hasher := sha256.New()
	size, err := io.Copy(hasher, file)
	if err != nil {
		return "", 0, err
	}

	return hex.EncodeToString(hasher.Sum(nil)), size, nil
}

func signAgentManifest(secret, version, filename, shaValue string, size int64) string {
	payload := fmt.Sprintf("%s\n%s\n%s\n%d", version, filename, shaValue, size)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(payload))
	return hex.EncodeToString(mac.Sum(nil))
}

// TriggerAgentUpdate 创建一个 agent 更新命令，agent 会在下次轮询命令时执行
func (h *MonitorHandler) TriggerAgentUpdate(c *gin.Context) {
	id := c.Param("id")

	host, ok := loadSSHHostForUser(h.DB, id, c)
	if !ok {
		denyHostAccess(c)
		return
	}

	cmd := models.AgentCommand{
		HostID:  host.ID,
		Command: "update",
	}
	if err := h.DB.Create(&cmd).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create command"})
		return
	}

	// Broadcast an immediate agent_event to update UI status
	monitor.GlobalHub.AgentEvent(monitor.AgentEvent{HostID: uint(host.ID), Event: "command", Message: "updating"})

	c.JSON(http.StatusOK, gin.H{"success": true})
}

// GetAgentCommands returns pending commands for an agent (authenticated by secret)
func (h *MonitorHandler) GetAgentCommands(c *gin.Context) {
	host, err := h.authenticateAgentRequest(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var cmds []models.AgentCommand
	if err := h.DB.Where("host_id = ? AND processed = ?", host.ID, false).Find(&cmds).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to query commands"})
		return
	}

	// Mark as processed (simple semantics: one-time delivery)
	now := time.Now()
	var ids []uint
	for _, ccmd := range cmds {
		ids = append(ids, ccmd.ID)
	}
	if len(ids) > 0 {
		h.DB.Model(&models.AgentCommand{}).Where("id IN ?", ids).Updates(map[string]interface{}{"processed": true, "processed_at": &now})
	}

	c.JSON(http.StatusOK, gin.H{"commands": cmds})
}
