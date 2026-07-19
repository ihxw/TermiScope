package monitor

import (
	"log"
	"strings"
)

// rebootUptimeThreshold: counters likely reset after reboot when uptime is below this (seconds).
const rebootUptimeThreshold = uint64(600)

// NormalizeTrafficCounterMode returns the canonical traffic billing mode.
func NormalizeTrafficCounterMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "rx":
		return "rx"
	case "tx":
		return "tx"
	case "both", "total", "":
		return "total"
	default:
		return "total"
	}
}

// BillableTraffic returns the measured traffic for a configured billing mode.
func BillableTraffic(mode string, rx, tx uint64) uint64 {
	switch NormalizeTrafficCounterMode(mode) {
	case "rx":
		return rx
	case "tx":
		return tx
	default:
		return rx + tx
	}
}

// IsVirtualInterface reports whether an interface name should be excluded from auto traffic totals.
func IsVirtualInterface(name string) bool {
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" || name == "lo" {
		return true
	}
	prefixes := []string{
		"docker", "veth", "br-", "tun", "cni", "flannel", "calico", "kube-ipvs",
		"virbr", "vmnet", "vboxnet", "vethernet", "npcap", "loopback",
	}
	for _, p := range prefixes {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

// SumAutoTrafficTotals sums non-virtual interfaces; falls back to agent totals when no per-interface data.
func SumAutoTrafficTotals(data MetricData) (rx, tx uint64) {
	if len(data.Interfaces) == 0 {
		return data.NetRx, data.NetTx
	}
	for _, iface := range data.Interfaces {
		if IsVirtualInterface(iface.Name) {
			continue
		}
		rx += iface.Rx
		tx += iface.Tx
	}
	return rx, tx
}

// ComputeTrafficTotals returns byte counters for monthly billing and live rates using host net_interface config.
func ComputeTrafficTotals(netInterface string, data MetricData) (rx, tx uint64) {
	netInterface = strings.TrimSpace(netInterface)
	if netInterface == "" || netInterface == "auto" {
		return SumAutoTrafficTotals(data)
	}

	targets := strings.Split(netInterface, ",")
	var foundAny bool
	for _, target := range targets {
		target = strings.TrimSpace(target)
		if target == "" {
			continue
		}
		for _, iface := range data.Interfaces {
			if strings.EqualFold(iface.Name, target) {
				rx += iface.Rx
				tx += iface.Tx
				foundAny = true
				break
			}
		}
	}
	if !foundAny {
		// Stale/wrong names: use auto filter instead of raw agent totals (avoids docker spikes).
		return SumAutoTrafficTotals(data)
	}
	return rx, tx
}

// ComputeTrafficDelta calculates bytes to add to monthly counters from kernel cumulative counters.
func ComputeTrafficDelta(lastRawRx, lastRawTx, currentRx, currentTx, uptimeSec uint64, hostID uint) (deltaRx, deltaTx uint64) {
	deltaRx = trafficDeltaOne(lastRawRx, currentRx, uptimeSec, hostID, "rx")
	deltaTx = trafficDeltaOne(lastRawTx, currentTx, uptimeSec, hostID, "tx")
	return deltaRx, deltaTx
}

func trafficDeltaOne(lastRaw, current, uptimeSec uint64, hostID uint, direction string) uint64 {
	if lastRaw == 0 {
		return 0
	}
	if current >= lastRaw {
		return current - lastRaw
	}
	// Counter dropped: reboot (kernel counters reset) vs. filter/config change.
	if uptimeSec < rebootUptimeThreshold {
		log.Printf("Traffic: host %d %s reboot detected (last=%d current=%d uptime=%ds), delta=current",
			hostID, direction, lastRaw, current, uptimeSec)
		return current
	}
	log.Printf("Traffic: host %d %s baseline realigned (last=%d current=%d uptime=%ds), delta=0",
		hostID, direction, lastRaw, current, uptimeSec)
	return 0
}

// SafeRate returns bytes/sec avoiding uint64 underflow when counters decrease.
func SafeRate(current, previous, timeDiffSec uint64) uint64 {
	if timeDiffSec == 0 || current < previous {
		return 0
	}
	return (current - previous) / timeDiffSec
}
