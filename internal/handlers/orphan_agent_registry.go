package handlers

import (
	"sort"
	"sync"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

const (
	orphanAgentMaxEntries = 256
	orphanAgentIPCap      = 8
)

// OrphanAgentReport is an agent still sending monitor traffic for a deleted/unknown host_id.
type OrphanAgentReport struct {
	HostID      uint      `json:"host_id"`
	ClientIPs   []string  `json:"client_ips"`
	Hostnames   []string  `json:"hostnames"`
	Macs        []string  `json:"macs"`
	HitCount    uint64    `json:"hit_count"`
	FirstSeenAt time.Time `json:"first_seen_at"`
	LastSeenAt  time.Time `json:"last_seen_at"`
}

type orphanAgentEntry struct {
	clientIPs map[string]struct{}
	hostnames map[string]struct{}
	macs      map[string]struct{}
	hitCount  uint64
	firstSeen time.Time
	lastSeen  time.Time
}

var (
	orphanAgentMu sync.RWMutex
	orphanAgents  = make(map[uint]*orphanAgentEntry)
)

func recordOrphanPulse(hostID uint, clientIP string, hostname string, mac string) {
	if hostID == 0 {
		return
	}
	now := time.Now()
	if clientIP == "" {
		clientIP = "unknown"
	}
	if hostname == "" {
		hostname = "unknown"
	}
	if mac == "" {
		mac = "unknown"
	}

	orphanAgentMu.Lock()
	defer orphanAgentMu.Unlock()

	entry, ok := orphanAgents[hostID]
	if !ok {
		if len(orphanAgents) >= orphanAgentMaxEntries {
			evictOldestOrphanLocked()
		}
		entry = &orphanAgentEntry{
			clientIPs: make(map[string]struct{}),
			hostnames: make(map[string]struct{}),
			macs:      make(map[string]struct{}),
			firstSeen: now,
		}
		orphanAgents[hostID] = entry
	}

	entry.hitCount++
	entry.lastSeen = now
	if len(entry.clientIPs) < orphanAgentIPCap {
		entry.clientIPs[clientIP] = struct{}{}
	}
	if len(entry.hostnames) < 8 {
		entry.hostnames[hostname] = struct{}{}
	}
	if len(entry.macs) < 8 {
		entry.macs[mac] = struct{}{}
	}

	logOrphanPulseOnce(hostID)
}

// clearOrphanPulse removes a stale orphan record once we know the host is genuinely alive.
// Without this, transient DB hiccups or "host was deleted then restored" scenarios would leave
// permanent ghost entries on the orphan page even when the host is reporting normally again.
func clearOrphanPulse(hostID uint) {
	if hostID == 0 {
		return
	}
	orphanAgentMu.Lock()
	if _, ok := orphanAgents[hostID]; ok {
		delete(orphanAgents, hostID)
	}
	orphanAgentMu.Unlock()
}

func evictOldestOrphanLocked() {
	var oldestID uint
	var oldest time.Time
	first := true
	for id, e := range orphanAgents {
		if first || e.lastSeen.Before(oldest) {
			oldest = e.lastSeen
			oldestID = id
			first = false
		}
	}
	if !first {
		delete(orphanAgents, oldestID)
	}
}

func listOrphanAgents() []OrphanAgentReport {
	return listOrphanAgentsFiltered(nil)
}

// listOrphanAgentsFiltered drops in-memory entries whose host_id now resolves to an existing
// (non-soft-deleted) host. This makes the orphan page self-heal after a transient miss without
// requiring the operator to manually dismiss false positives.
func listOrphanAgentsFiltered(db *gorm.DB) []OrphanAgentReport {
	orphanAgentMu.Lock()
	defer orphanAgentMu.Unlock()

	out := make([]OrphanAgentReport, 0, len(orphanAgents))
	for hostID, e := range orphanAgents {
		// Clean up entries that have been silent for more than 15 minutes.
		// If an agent has been uninstalled or stopped, it shouldn't haunt the orphan page forever.
		if time.Since(e.lastSeen) > 15*time.Minute {
			delete(orphanAgents, hostID)
			continue
		}
		if db != nil && hostStillExists(db, hostID) {
			delete(orphanAgents, hostID)
			invalidatePulseHostCache(hostID)
			continue
		}
		ips := make([]string, 0, len(e.clientIPs))
		for ip := range e.clientIPs {
			ips = append(ips, ip)
		}
		sort.Strings(ips)

		hostnames := make([]string, 0, len(e.hostnames))
		for h := range e.hostnames {
			hostnames = append(hostnames, h)
		}
		sort.Strings(hostnames)

		macs := make([]string, 0, len(e.macs))
		for m := range e.macs {
			macs = append(macs, m)
		}
		sort.Strings(macs)

		out = append(out, OrphanAgentReport{
			HostID:      hostID,
			ClientIPs:   ips,
			Hostnames:   hostnames,
			Macs:        macs,
			HitCount:    e.hitCount,
			FirstSeenAt: e.firstSeen,
			LastSeenAt:  e.lastSeen,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].LastSeenAt.After(out[j].LastSeenAt)
	})
	return out
}

func hostStillExists(db *gorm.DB, hostID uint) bool {
	var count int64
	if err := db.Model(&models.SSHHost{}).Where("id = ?", hostID).Count(&count).Error; err != nil {
		return false
	}
	return count > 0
}

func dismissOrphanAgent(hostID uint) {
	orphanAgentMu.Lock()
	delete(orphanAgents, hostID)
	orphanAgentMu.Unlock()
	invalidatePulseHostCache(hostID)
}
