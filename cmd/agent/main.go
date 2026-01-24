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
	"strings"
	"time"

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

// MetricData matches the termiscope backend struct
type MetricData struct {
	HostID       uint64          `json:"host_id"`
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

	// Version is set during build via ldflags (-X main.Version=x.x.x)
	Version = "dev"

	cachedOS       string
	cachedHostname string
	cachedCpuModel string
	cachedCpuCount int
	cachedCpuMhz   float64
)

func main() {
	flag.StringVar(&serverURL, "server", "", "Server URL (e.g. http://localhost:8080)")
	flag.StringVar(&secret, "secret", "", "Monitor Secret")
	flag.Uint64Var(&hostID, "id", 0, "Host ID")
	insecure := flag.Bool("insecure", false, "Skip SSL verification")
	flag.Parse()

	if serverURL == "" || secret == "" || hostID == 0 {
		log.Fatal("Usage: agent -server <url> -secret <secret> -id <host_id>")
	}

	initSystemInfo()

	log.Printf("TermiScope Agent v%s started for Host %d. Target: %s. OS: %s", Version, hostID, serverURL, cachedOS)

	transport := &http.Transport{}
	if *insecure {
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
		log.Printf("Failed to report metrics: %v", err)
	}

	for {
		metrics := collectMetrics()
		if err := sendMetrics(client, metrics); err != nil {
			log.Printf("Failed to report metrics: %v", err)
		}
		time.Sleep(2 * time.Second)
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
		cachedCpuCount = len(cpuInfo) // Logical cores
		cachedCpuMhz = cpuInfo[0].Mhz
	}
}

func collectMetrics() MetricData {
	data := MetricData{
		HostID:       hostID,
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

	// Disk - Aggregate all physical partitions (filter out tmpfs, devfs, etc.)
	partitions, err := disk.Partitions(false) // false = exclude pseudo filesystems
	if err == nil {
		var totalSize, totalUsed uint64
		for _, partition := range partitions {
			// Skip pseudo filesystems
			if strings.HasPrefix(partition.Fstype, "tmpfs") ||
				strings.HasPrefix(partition.Fstype, "devtmpfs") ||
				strings.HasPrefix(partition.Fstype, "devfs") ||
				strings.HasPrefix(partition.Fstype, "proc") ||
				strings.HasPrefix(partition.Fstype, "sysfs") ||
				strings.HasPrefix(partition.Fstype, "cgroup") ||
				strings.HasPrefix(partition.Fstype, "overlay") ||
				partition.Fstype == "" {
				continue
			}

			// Get usage for this partition
			if usage, err := disk.Usage(partition.Mountpoint); err == nil {
				totalSize += usage.Total
				totalUsed += usage.Used
			}
		}
		data.DiskTotal = totalSize
		data.DiskUsed = totalUsed
	}

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
