package handlers

import (
	"sort"
	"sync"
	"time"
)

const (
	orphanAgentMaxEntries = 256
	orphanAgentIPCap      = 8
)

// OrphanAgentReport is an agent still sending monitor traffic for a deleted/unknown host_id.
type OrphanAgentReport struct {
	HostID      uint      `json:"host_id"`
	ClientIPs   []string  `json:"client_ips"`
	HitCount    uint64    `json:"hit_count"`
	FirstSeenAt time.Time `json:"first_seen_at"`
	LastSeenAt  time.Time `json:"last_seen_at"`
}

type orphanAgentEntry struct {
	clientIPs map[string]struct{}
	hitCount  uint64
	firstSeen time.Time
	lastSeen  time.Time
}

var (
	orphanAgentMu sync.RWMutex
	orphanAgents  = make(map[uint]*orphanAgentEntry)
)

func recordOrphanPulse(hostID uint, clientIP string) {
	now := time.Now()
	if clientIP == "" {
		clientIP = "unknown"
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
			firstSeen: now,
		}
		orphanAgents[hostID] = entry
	}

	entry.hitCount++
	entry.lastSeen = now
	if len(entry.clientIPs) < orphanAgentIPCap {
		entry.clientIPs[clientIP] = struct{}{}
	}

	logOrphanPulseOnce(hostID)
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
	orphanAgentMu.RLock()
	defer orphanAgentMu.RUnlock()

	out := make([]OrphanAgentReport, 0, len(orphanAgents))
	for hostID, e := range orphanAgents {
		ips := make([]string, 0, len(e.clientIPs))
		for ip := range e.clientIPs {
			ips = append(ips, ip)
		}
		sort.Strings(ips)
		out = append(out, OrphanAgentReport{
			HostID:      hostID,
			ClientIPs:   ips,
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

func dismissOrphanAgent(hostID uint) {
	orphanAgentMu.Lock()
	delete(orphanAgents, hostID)
	orphanAgentMu.Unlock()
	invalidatePulseHostCache(hostID)
}
