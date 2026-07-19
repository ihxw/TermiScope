package monitor

import (
	"time"

	"github.com/ihxw/termiscope/internal/models"
)

type PulseTransition struct {
	Metric                   MetricData
	Dirty                    bool
	Stale                    bool
	DeltaRx                  uint64
	DeltaTx                  uint64
	TrafficAlert             bool
	TrafficUsed              uint64
	TrafficPercent           uint64
	CameOnline               bool
	SuppressBackOnlineNotice bool
}

func IsStalePulse(host *models.SSHHost, data MetricData) bool {
	return data.Timestamp > 0 && data.Timestamp <= host.LastAgentTimestamp
}

// AdvancePulse applies one accepted agent pulse to the host's in-memory state.
// Persistence, notifications, and broadcasting remain adapters owned by the caller.
func AdvancePulse(host *models.SSHHost, data MetricData, now time.Time) PulseTransition {
	result := PulseTransition{Metric: data}
	if IsStalePulse(host, data) {
		result.Stale = true
		return result
	}

	if data.Timestamp > 0 {
		host.LastAgentTimestamp = data.Timestamp
		result.Dirty = true
	}
	if !host.MonitorEnabled {
		host.MonitorEnabled = true
		result.Dirty = true
	}

	currentRx, currentTx := ComputeTrafficTotals(host.NetInterface, data)
	result.Metric.NetRx = currentRx
	result.Metric.NetTx = currentTx
	result.DeltaRx, result.DeltaTx = ComputeTrafficDelta(
		host.NetLastRawRx, host.NetLastRawTx,
		currentRx, currentTx,
		data.Uptime, host.ID,
	)

	if result.DeltaRx > 0 || result.DeltaTx > 0 {
		host.NetMonthlyRx += result.DeltaRx
		host.NetMonthlyTx += result.DeltaTx
		result.Dirty = true

		if host.NetTrafficLimit > 0 {
			measured := BillableTraffic(host.NetTrafficCounterMode, host.NetMonthlyRx, host.NetMonthlyTx)
			result.TrafficUsed = measured + host.NetTrafficUsedAdjustment
			result.TrafficPercent = result.TrafficUsed * 100 / host.NetTrafficLimit
			threshold := uint64(host.NotifyTrafficThreshold)
			if threshold == 0 {
				threshold = 90
			}
			if host.NotifyTrafficEnabled && result.TrafficPercent >= threshold && !host.TrafficAlerted {
				host.TrafficAlerted = true
				result.TrafficAlert = true
			}
		}
	}

	if host.NetLastRawRx != currentRx || host.NetLastRawTx != currentTx {
		host.NetLastRawRx = currentRx
		host.NetLastRawTx = currentTx
		result.Dirty = true
	}

	if !host.LastPulse.Equal(now) {
		host.LastPulse = now
		result.Dirty = true
	}
	if data.AgentVersion != "" && host.AgentVersion != data.AgentVersion {
		host.AgentVersion = data.AgentVersion
		result.Dirty = true
	}
	if host.AgentTransferPort != data.AgentTransferPort || host.AgentTransferCertSHA256 != data.AgentTransferCertSHA256 {
		host.AgentTransferPort = data.AgentTransferPort
		host.AgentTransferCertSHA256 = data.AgentTransferCertSHA256
		result.Dirty = true
	}
	if host.AgentTransferRelay != data.AgentTransferRelay {
		host.AgentTransferRelay = data.AgentTransferRelay
		result.Dirty = true
	}

	if host.Status != "online" {
		host.Status = "online"
		result.CameOnline = true
		result.SuppressBackOnlineNotice = host.OfflineAt != nil && now.Sub(*host.OfflineAt) < time.Minute
		host.OfflineAt = nil
		host.OfflineNotified = false
		result.Dirty = true
	}

	return result
}
