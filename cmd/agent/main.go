package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"runtime"
	"sort"
	"strings"
	"time"
	"path/filepath"

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
	partitions, err := disk.Partitions(true)
	if err != nil {
		return nil, 0, 0
	}

	seenKeys := make(map[string]struct{})
	seenMounts := make(map[string]struct{})
	seenPools := make(map[string]struct{})
	seenDevIDs := make(map[uint64]struct{})
	seenPhysicalDevices := make(map[string]struct{})
	disks := make([]DiskData, 0, len(partitions))
	var totalUsed uint64
	var totalSize uint64

	for _, partition := range partitions {
		mountPoint := strings.TrimSpace(partition.Mountpoint)
		if shouldSkipPartition(partition, mountPoint) {
			continue
		}

		usage, err := disk.Usage(mountPoint)
		if err != nil || usage.Total == 0 {
			continue
		}

		if _, exists := seenMounts[mountPoint]; exists {
			continue
		}

		diskKey := diskIdentityKey(partition)
		if _, exists := seenKeys[diskKey]; exists {
			continue
		}

		// Deduplicate by strict Unix Device ID if possible
		devID := getDiskID(mountPoint)
		if devID != 0 {
			if _, exists := seenDevIDs[devID]; exists {
				continue
			}
			seenDevIDs[devID] = struct{}{}
		}

		// Also deduplicate by underlying physical device (merge partitions on same disk)
		phys := getPhysicalDevice(diskKey)
		if phys != "" {
			if _, exists := seenPhysicalDevices[phys]; exists {
				// Already counted this physical disk
				continue
			}
			seenPhysicalDevices[phys] = struct{}{}
		}

		// Deduplicate pooled filesystems (ZFS, Btrfs, APFS)
		lowerFS := strings.ToLower(strings.TrimSpace(partition.Fstype))
		if lowerFS == "zfs" || lowerFS == "btrfs" || lowerFS == "apfs" {
			// They share identical pool size
			poolKey := fmt.Sprintf("%s-%d", lowerFS, usage.Total)
			if _, exists := seenPools[poolKey]; exists {
				continue
			}
			seenPools[poolKey] = struct{}{}
		}

		seenMounts[mountPoint] = struct{}{}
		seenKeys[diskKey] = struct{}{}

		disks = append(disks, DiskData{
			MountPoint: mountPoint,
			Used:       usage.Used,
			Total:      usage.Total,
		})
		totalSize += usage.Total
		totalUsed += usage.Used
	}

	if len(disks) == 0 && runtime.GOOS != "windows" {
		if usage, err := disk.Usage("/"); err == nil && usage.Total > 0 {
			disks = append(disks, DiskData{MountPoint: "/", Used: usage.Used, Total: usage.Total})
			totalSize = usage.Total
			totalUsed = usage.Used
		}
	}

	sort.Slice(disks, func(i, j int) bool {
		return disks[i].MountPoint < disks[j].MountPoint
	})

	return disks, totalUsed, totalSize
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
