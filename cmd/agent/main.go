package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/kardianos/service"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

// InterfaceData holds per-interface metrics
type InterfaceData struct {
	Name string   `json:"name"`
	Rx   uint64   `json:"rx"`
	Tx   uint64   `json:"tx"`
	IPs  []string `json:"ips"`
	Mac  string   `json:"mac"`
}

type DiskData struct {
	MountPoint string `json:"mount_point"`
	Used       uint64 `json:"used"`
	Total      uint64 `json:"total"`
}

// MetricData matches the termiscope backend struct
type MetricData struct {
	HostID       uint64          `json:"host_id"`
	Timestamp    int64           `json:"timestamp"`
	AgentVersion string          `json:"agent_version"`
	Uptime       uint64          `json:"uptime"`
	CPU          float64         `json:"cpu"`
	CpuCount     int             `json:"cpu_count"`
	CpuModel     string          `json:"cpu_model"`
	CpuMhz       float64         `json:"cpu_mhz"`
	MemUsed      uint64          `json:"mem_used"`
	MemTotal     uint64          `json:"mem_total"`
	DiskUsed     uint64          `json:"disk_used"`
	DiskTotal    uint64          `json:"disk_total"`
	Disks        []DiskData      `json:"disks"`
	NetRx        uint64          `json:"net_rx"` // Sum of all interfaces
	NetTx        uint64          `json:"net_tx"` // Sum of all interfaces
	Interfaces   []InterfaceData `json:"interfaces"`
	OS           string          `json:"os"`
	Hostname     string          `json:"hostname"`
}

var (
	serverURL string
	secret    string
	hostID    uint64
	insecure  bool

	// Version is set during build via ldflags (-X main.Version=x.x.x)
	Version = "dev"

	cachedOS       string
	cachedHostname string
	cachedCpuModel string
	cachedCpuCount int
	cachedCpuMhz   float64

	logger service.Logger
)

// Program structures
type program struct {
	exit chan struct{}
}

func (p *program) Start(s service.Service) error {
	// Start should not block. Do the actual work async.
	p.exit = make(chan struct{})
	go p.run()
	return nil
}

func (p *program) run() {
	// Initialize system info
	initSystemInfo()

	if logger != nil {
		logger.Infof("TermiScope Agent v%s started for Host %d. Target: %s. OS: %s", Version, hostID, serverURL, cachedOS)
	} else {
		log.Printf("TermiScope Agent v%s started for Host %d. Target: %s. OS: %s", Version, hostID, serverURL, cachedOS)
	}

	transport := &http.Transport{}
	if insecure {
		transport.TLSClientConfig = &tls.Config{InsecureSkipVerify: true}
	}

	client := &http.Client{
		Timeout:   5 * time.Second,
		Transport: transport,
	}

	// Start Network Monitor
	netMon := NewNetworkMonitor(client)
	netMon.StartSimple()

	// Start polling server-issued commands
	stopCmdCh := make(chan struct{})
	go pollAgentCommands(client, stopCmdCh)

	// Initial system metrics collection
	metrics := collectMetrics()
	if err := sendMetrics(client, metrics); err != nil {
		logError("Failed to report metrics: %v", err)
	} else if err := attemptAgentSelfUpdate(client); err != nil {
		logError("Agent self-update check failed: %v", err)
	}

	ticker := time.NewTicker(2 * time.Second)
	updateTicker := time.NewTicker(agentUpdateCheckInterval)
	defer updateTicker.Stop()
	nextUpdateAttempt := time.Now()
	for {
		select {
		case <-ticker.C:
			metrics := collectMetrics()
			if err := sendMetrics(client, metrics); err != nil {
				logError("Failed to report metrics: %v", err)
			}
		case <-updateTicker.C:
			if time.Now().Before(nextUpdateAttempt) {
				continue
			}
			if err := attemptAgentSelfUpdate(client); err != nil {
				logError("Agent self-update check failed: %v", err)
				nextUpdateAttempt = time.Now().Add(agentUpdateRetryDelay)
			} else {
				nextUpdateAttempt = time.Now().Add(agentUpdateCheckInterval)
			}
		case <-p.exit:
			ticker.Stop()
			return
		}
	}
}

func (p *program) Stop(s service.Service) error {
	// Stop should not block. Return with a few seconds.
	close(p.exit)
	if logger != nil {
		logger.Info("TermiScope Agent stopping")
	}
	return nil
}

func logError(format string, v ...interface{}) {
	if logger != nil {
		logger.Errorf(format, v...)
	} else {
		log.Printf(format, v...)
	}
}

func main() {
	flag.StringVar(&serverURL, "server", "", "Server URL (e.g. http://localhost:8080)")
	flag.StringVar(&secret, "secret", "", "Monitor Secret")
	flag.Uint64Var(&hostID, "id", 0, "Host ID")
	flag.BoolVar(&insecure, "insecure", false, "Skip SSL verification")

	// Service control flags
	svcFlag := flag.String("service", "", "Control the system service.")
	flag.Parse()

	svcConfig := &service.Config{
		Name:        "TermiScopeAgent",
		DisplayName: "TermiScope Monitor Agent",
		Description: "TermiScope monitoring agent service.",
		Arguments:   []string{"-server", serverURL, "-secret", secret, "-id", fmt.Sprintf("%d", hostID)},
	}

	// Propagate insecure flag if set
	if insecure {
		svcConfig.Arguments = append(svcConfig.Arguments, "-insecure")
	}

	prg := &program{}
	s, err := service.New(prg, svcConfig)
	if err != nil {
		log.Fatal(err)
	}

	logger, err = s.Logger(nil)
	if err != nil {
		log.Fatal(err)
	}

	if len(*svcFlag) != 0 {
		err := service.Control(s, *svcFlag)
		if err != nil {
			log.Printf("Valid actions: %q\n", service.ControlAction)
			log.Fatal(err)
		}
		return
	}

	// Run validation only if not controlling service (and not running as service)
	// When running as service, flags might not be parsed from command line but from arguments
	// But s.Run() parses arguments too? No, service arguments are passed to executable.
	// Logic: If plain run, check args. If service run, logic inside run() will likely use global vars.
	// However, flags are parsed above.

	// When running as a service, the arguments are passed to the binary.
	// flag.Parse() handles them.

	if serverURL == "" || secret == "" || hostID == 0 {
		// Only fatal if we are NOT installing/uninstalling/status checking
		// If we are actually trying to run (interactive or service)
		if len(*svcFlag) == 0 {
			// Check if we are being run by service manager?
			// service.Interactive() returns true if running in terminal.
			if service.Interactive() {
				log.Fatal("Usage: agent -server <url> -secret <secret> -id <host_id> [-service install|uninstall|start|stop]")
			}
			// If not interactive, we might be running as service but missing args?
			// We'll let it proceed and fail in run() or just log error.
		}
	}

	err = s.Run()
	if err != nil {
		logger.Error(err)
	}
}

func initSystemInfo() {
	info, err := host.Info()
	if err == nil {
		cachedHostname = info.Hostname
		cachedOS = fmt.Sprintf("%s %s", info.OS, info.Platform)
	} else {
		// Fallback
		cachedOS = runtime.GOOS
	}

	// Cache CPU Info
	if cpuInfo, err := cpu.Info(); err == nil && len(cpuInfo) > 0 {
		cachedCpuModel = cpuInfo[0].ModelName
		cachedCpuMhz = cpuInfo[0].Mhz
	}
	// Use Counts for accurate logical core count
	if count, err := cpu.Counts(true); err == nil {
		cachedCpuCount = int(count)
	} else if len(cachedCpuModel) > 0 {
		// Fallback if Counts fails but Info succeeded (unlikely)
		// We might need to call Info again or just check length if we kept the slice
		// But simplest is to just re-call or trust Counts.
		// Let's stick to Counts(true). If it fails, we default to 0.
	}
}

func collectMetrics() MetricData {
	data := MetricData{
		HostID:       hostID,
		Timestamp:    time.Now().Unix(),
		AgentVersion: Version,
		OS:           cachedOS,
		Hostname:     cachedHostname,
		CpuCount:     cachedCpuCount,
		CpuModel:     cachedCpuModel,
		CpuMhz:       cachedCpuMhz,
	}

	// Uptime
	if uptime, err := host.Uptime(); err == nil {
		data.Uptime = uptime
	}

	// Memory
	if v, err := mem.VirtualMemory(); err == nil {
		data.MemTotal = v.Total
		data.MemUsed = v.Used
	}

	// CPU
	if percent, err := cpu.Percent(0, false); err == nil && len(percent) > 0 {
		data.CPU = percent[0]
	}

	data.Disks, data.DiskUsed, data.DiskTotal = collectDiskMetrics()

	// Network
	if counters, err := net.IOCounters(true); err == nil {
		data.NetRx = 0
		data.NetTx = 0
		data.Interfaces = []InterfaceData{}

		// Get Static Info (IPs, MAC)
		interfaces, _ := net.Interfaces()
		interfaceMap := make(map[string]net.InterfaceStat)
		for _, iface := range interfaces {
			interfaceMap[iface.Name] = iface
		}

		for _, nic := range counters {
			// Skip loopback or pseudo interfaces if desired, but gopsutil usually gives real ones
			// Simulating the previous logic of skipping 'lo'
			if nic.Name == "lo" || nic.Name == "Loopback Pseudo-Interface 1" {
				continue
			}

			data.NetRx += nic.BytesRecv
			data.NetTx += nic.BytesSent

			// Find static info
			var ips []string
			var mac string
			if static, ok := interfaceMap[nic.Name]; ok {
				mac = static.HardwareAddr
				for _, addr := range static.Addrs {
					ips = append(ips, addr.Addr)
				}
			}

			data.Interfaces = append(data.Interfaces, InterfaceData{
				Name: nic.Name,
				Rx:   nic.BytesRecv,
				Tx:   nic.BytesSent,
				IPs:  ips,
				Mac:  mac,
			})
		}
	}

	return data
}

func collectDiskMetrics() ([]DiskData, uint64, uint64) {
	// Use physical disk-based collection on Linux (aggregates partitions)
	if runtime.GOOS == "linux" {
		if d, used, size, err := collectDiskMetricsPhysical(); err == nil && len(d) > 0 {
			return d, used, size
		}
		// Fallthrough to df-based method on error
	}

	// Fallback: use df-based method
	d, used, size, err := collectDiskMetricsDf()
	if err != nil {
		return nil, 0, 0
	}
	return d, used, size
}

// collectDiskMetricsHybrid uses gopsutil with df fallback for reliable disk statistics.
// This approach correctly handles LVM, Btrfs pools, and other complex storage configurations.
func collectDiskMetricsHybrid() ([]DiskData, uint64, uint64, error) {
	// Primary method: Use gopsutil's disk.Partitions and disk.Usage
	// This is more reliable than parsing command output
	partitions, err := disk.Partitions(true)
	if err != nil {
		// Fallback to df-based method if gopsutil fails
		return collectDiskMetricsDf()
	}

	// Global seen set to prevent double-counting
	globalSeenMounts := make(map[string]struct{})
	globalSeenDevIDs := make(map[uint64]struct{})

	var disks []DiskData
	var totalUsed uint64
	var totalSize uint64

	for _, partition := range partitions {
		mountPoint := strings.TrimSpace(partition.Mountpoint)
		if shouldSkipPartition(partition, mountPoint) {
			continue
		}

		// Get usage using gopsutil (cross-platform, reliable)
		usage, err := disk.Usage(mountPoint)

		// Handle case where disk exists but usage cannot be determined
		// For example: unmounted disk, raw disk, or permission issues
		var used uint64
		var total uint64

		if err != nil {
			// Cannot get usage, but we still want to report the disk
			// Try to get size from lsblk or df fallback
			continue // Skip for now, will be handled by df fallback if needed
		}

		if usage.Total == 0 {
			// Disk with 0 total size, skip
			continue
		}

		used = usage.Used
		total = usage.Total

		// Skip if already seen this mountpoint
		if _, exists := globalSeenMounts[mountPoint]; exists {
			continue
		}

		// Deduplicate by device ID
		devID := getDiskID(mountPoint)
		if devID != 0 {
			if _, exists := globalSeenDevIDs[devID]; exists {
				continue
			}
			globalSeenDevIDs[devID] = struct{}{}
		}

		globalSeenMounts[mountPoint] = struct{}{}

		// Try to map to physical disk using lsblk
		physDevice := getPhysicalDeviceForMount(mountPoint, partition.Device)
		diskKey := physDevice
		if diskKey == "" {
			diskKey = partition.Device
		}

		disks = append(disks, DiskData{
			MountPoint: mountPoint,
			Used:       used,
			Total:      total,
		})
		totalUsed += used
		totalSize += total
	}

	if len(disks) == 0 {
		// Complete fallback to df method
		return collectDiskMetricsDf()
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize, nil
}

// collectDiskMetricsPhysical collects disk metrics by physical device.
// It aggregates usage across all partitions of the same physical disk.
func collectDiskMetricsPhysical() ([]DiskData, uint64, uint64, error) {
	// Step 1: Get all mountpoints with usage from df
	dfOut, err := exec.Command("df", "-B1", "-P", "-T").Output()
	if err != nil {
		return nil, 0, 0, err
	}

	// Map: mountpoint -> {used, total}
	mountData := make(map[string]struct {
		used  uint64
		total uint64
	})

	lines := strings.Split(string(dfOut), "\n")
	for i, line := range lines {
		if i == 0 {
			continue // Skip header
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 7 {
			continue
		}

		fsType := fields[1]
		totalStr := fields[2]
		usedStr := fields[3]
		mountPoint := fields[len(fields)-1]

		total, err := strconv.ParseUint(totalStr, 10, 64)
		if err != nil {
			continue
		}
		used, err := strconv.ParseUint(usedStr, 10, 64)
		if err != nil {
			continue
		}

		if shouldSkipFsType(fsType, mountPoint) {
			continue
		}

		mountData[mountPoint] = struct {
			used  uint64
			total uint64
		}{used: used, total: total}
	}

	// Step 2: Get physical disk to mountpoint mapping from lsblk
	// Use -o NAME,TYPE,MOUNTPOINT,PKNAME to get parent device
	lsblkOut, err := exec.Command("lsblk", "-rn", "-o", "NAME,TYPE,MOUNTPOINT,PKNAME").Output()
	if err != nil {
		// Fallback to df-based method
		return collectDiskMetricsDf()
	}

	// Map: physical disk -> {used, total}
	physicalDiskData := make(map[string]struct {
		used  uint64
		total uint64
	})

	// Map: device name -> physical disk
	deviceToDisk := make(map[string]string)

	lines = strings.Split(string(lsblkOut), "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}

		name := "/dev/" + fields[0]
		devType := fields[1]
		mountPoint := fields[2]
		parent := "/dev/" + fields[3]

		// Track physical disks
		if devType == "disk" {
			deviceToDisk[name] = name
			if _, exists := physicalDiskData[name]; !exists {
				physicalDiskData[name] = struct {
					used  uint64
					total uint64
				}{used: 0, total: 0}
			}
			continue
		}

		// Map child devices to their physical disk
		if parentDisk, exists := deviceToDisk[parent]; exists {
			deviceToDisk[name] = parentDisk
		}

		// If this device has a mountpoint, add its usage to the physical disk
		if mountPoint != "" && mountPoint != "[SWAP]" {
			if physicalDisk, exists := deviceToDisk[name]; exists {
				if data, mpExists := mountData[mountPoint]; mpExists {
					existing := physicalDiskData[physicalDisk]
					existing.used += data.used
					existing.total += data.total
					physicalDiskData[physicalDisk] = existing
				}
			}
		}
	}

	// Step 3: Build result
	var disks []DiskData
	var totalUsed uint64
	var totalSize uint64

	for disk, data := range physicalDiskData {
		if data.total == 0 {
			continue // Skip disks without mounted partitions
		}

		disks = append(disks, DiskData{
			MountPoint: disk,
			Used:       data.used,
			Total:      data.total,
		})
		totalUsed += data.used
		totalSize += data.total
	}

	if len(disks) == 0 {
		return collectDiskMetricsDf()
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize, nil
}

// collectDiskMetricsDf is a fallback method that parses df command output
func collectDiskMetricsDf() ([]DiskData, uint64, uint64, error) {
	dfOut, err := exec.Command("df", "-B1", "-P", "-T").Output()
	if err != nil {
		return nil, 0, 0, err
	}

	mountUsage := make(map[string]uint64)
	mountTotal := make(map[string]uint64)
	mountDevice := make(map[string]string)

	lines := strings.Split(string(dfOut), "\n")
	for i, line := range lines {
		if i == 0 {
			continue // Skip header
		}
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 7 {
			continue
		}

		fsType := fields[1]
		totalStr := fields[2]
		usedStr := fields[3]
		mountPoint := fields[len(fields)-1] // Use last field to handle long device names

		total, err := strconv.ParseUint(totalStr, 10, 64)
		if err != nil {
			continue
		}
		used, err := strconv.ParseUint(usedStr, 10, 64)
		if err != nil {
			continue
		}

		if shouldSkipFsType(fsType, mountPoint) {
			continue
		}

		mountUsage[mountPoint] = used
		mountTotal[mountPoint] = total
		mountDevice[mountPoint] = fields[0] // Store device name
	}

	var disks []DiskData
	var totalUsed uint64
	var totalSize uint64
	globalSeenMounts := make(map[string]struct{})
	// Track seen storage pools to avoid double-counting (e.g., LVM, Btrfs)
	// Key: "total-fstype" to identify unique storage pools
	seenPools := make(map[string]struct{})

	for mp, used := range mountUsage {
		if _, exists := globalSeenMounts[mp]; exists {
			continue
		}
		globalSeenMounts[mp] = struct{}{}

		total := mountTotal[mp]

		// Skip if total is 0 (invalid disk)
		if total == 0 {
			continue
		}

		// Skip duplicate storage pools (same total capacity)
		// This prevents double-counting LVM, Btrfs pools, etc.
		poolKey := fmt.Sprintf("%d", total)
		if _, exists := seenPools[poolKey]; exists {
			// Skip this mount point as it's a duplicate of the same pool
			continue
		}
		seenPools[poolKey] = struct{}{}

		// MountPoint should be the mount point, not the device name
		// Device name is stored for reference but we display mount point
		disks = append(disks, DiskData{
			MountPoint: mp, // Mount point (e.g., /fs, /vol1)
			Used:       used,
			Total:      total,
		})
		totalUsed += used
		totalSize += total
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize, nil
}

// getPhysicalDeviceForMount attempts to find the physical block device for a mount point
func getPhysicalDeviceForMount(mountPoint, device string) string {
	if device == "" {
		return ""
	}

	// Try to resolve the device to a physical disk
	return getPhysicalDevice(device)
}

// getPhysicalDevice attempts to derive the underlying physical block device
// for a given device path (e.g. /dev/sda1 -> /dev/sda, /dev/nvme0n1p1 -> /dev/nvme0n1).
// If it cannot determine a parent device, it returns the device path as-is.
// shouldSkipFsType determines if a filesystem type should be skipped
func shouldSkipFsType(fsType, mountPoint string) bool {
	lowerFS := strings.ToLower(strings.TrimSpace(fsType))
	lowerMount := strings.ToLower(strings.TrimSpace(mountPoint))

	pseudoFS := map[string]struct{}{
		"autofs":      {},
		"binfmt_misc": {},
		"cgroup":      {},
		"cgroup2":     {},
		"configfs":    {},
		"debugfs":     {},
		"devfs":       {},
		"devpts":      {},
		"devtmpfs":    {},
		"fusectl":     {},
		"hugetlbfs":   {},
		"mqueue":      {},
		"nsfs":        {},
		"overlay":     {}, // Skip overlay unless it's root
		"proc":        {},
		"procfs":      {},
		"pstore":      {},
		"securityfs":  {},
		"selinuxfs":   {},
		"squashfs":    {},
		"sysfs":       {},
		"tmpfs":       {},
		"tracefs":     {},
	}

	if _, skip := pseudoFS[lowerFS]; skip {
		return true
	}

	// Keep overlay only for root filesystem
	if lowerFS == "overlay" && lowerMount != "/" {
		return true
	}

	// Skip virtual mount points
	skipMountPrefixes := []string{"/proc", "/sys", "/dev", "/run", "/snap"}
	for _, prefix := range skipMountPrefixes {
		if lowerMount == prefix || strings.HasPrefix(lowerMount, prefix+"/") {
			return true
		}
	}

	return false
}

func shouldSkipPartition(partition disk.PartitionStat, mountPoint string) bool {
	if mountPoint == "" {
		return true
	}

	lowerMount := strings.ToLower(mountPoint)
	lowerFS := strings.ToLower(strings.TrimSpace(partition.Fstype))
	lowerDevice := strings.ToLower(strings.TrimSpace(partition.Device))

	pseudoFS := map[string]struct{}{
		"autofs":      {},
		"binfmt_misc": {},
		"cgroup":      {},
		"cgroup2":     {},
		"configfs":    {},
		"debugfs":     {},
		"devfs":       {},
		"devpts":      {},
		"devtmpfs":    {},
		"fusectl":     {},
		"hugetlbfs":   {},
		"mqueue":      {},
		"nsfs":        {},
		"proc":        {},
		"procfs":      {},
		"pstore":      {},
		"securityfs":  {},
		"selinuxfs":   {},
		"squashfs":    {},
		"sysfs":       {},
		"tmpfs":       {},
		"tracefs":     {},
	}

	if _, skip := pseudoFS[lowerFS]; skip {
		return true
	}

	if lowerFS == "overlay" && lowerMount != "/" {
		return true
	}

	skipMountPrefixes := []string{"/proc", "/sys", "/dev", "/run", "/snap"}
	for _, prefix := range skipMountPrefixes {
		if lowerMount == prefix || strings.HasPrefix(lowerMount, prefix+"/") {
			return true
		}
	}

	if runtime.GOOS == "darwin" && strings.HasPrefix(lowerMount, "/system/volumes/") {
		return true
	}

	skipDevicePrefixes := []string{"autofs", "devfs", "map ", "none", "proc", "sys", "tmpfs"}
	for _, prefix := range skipDevicePrefixes {
		if strings.HasPrefix(lowerDevice, prefix) {
			return true
		}
	}

	return false
}

func diskIdentityKey(partition disk.PartitionStat) string {
	device := strings.TrimSpace(partition.Device)
	if device == "" {
		return strings.TrimSpace(partition.Mountpoint)
	}

	// resolve symlinks like /dev/root -> /dev/mmcblk0p1
	if resolved, err := filepath.EvalSymlinks(device); err == nil {
		device = resolved
	}

	return device

}

func sendMetrics(client *http.Client, data MetricData) error {
	jsonData, err := json.Marshal(data)
	if err != nil {
		return err
	}

	req, err := http.NewRequest("POST", serverURL+"/api/monitor/pulse", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("server returned status: %d", resp.StatusCode)
	}

	return nil
}

func sendAgentEvent(client *http.Client, event string, message string) error {
	data := map[string]interface{}{
		"host_id": hostID,
		"event":   event,
		"message": message,
	}
	jsonData, err := json.Marshal(data)
	if err != nil {
		return err
	}
	req, err := http.NewRequest("POST", serverURL+"/api/monitor/agent-event", bytes.NewBuffer(jsonData))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+secret)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return fmt.Errorf("server returned status: %d", resp.StatusCode)
	}

	return nil
}
