package handlers

import (
	"testing"
	"time"
)

func TestRecordAndListOrphanAgents(t *testing.T) {
	orphanAgentMu.Lock()
	orphanAgents = make(map[uint]*orphanAgentEntry)
	orphanAgentMu.Unlock()

	recordOrphanPulse(21, "1.2.3.4")
	recordOrphanPulse(21, "5.6.7.8")

	list := listOrphanAgents()
	if len(list) != 1 {
		t.Fatalf("expected 1 orphan, got %d", len(list))
	}
	if list[0].HostID != 21 {
		t.Fatalf("expected host 21, got %d", list[0].HostID)
	}
	if list[0].HitCount < 2 {
		t.Fatalf("expected hit count >= 2, got %d", list[0].HitCount)
	}
	if len(list[0].ClientIPs) != 2 {
		t.Fatalf("expected 2 IPs, got %v", list[0].ClientIPs)
	}

	dismissOrphanAgent(21)
	if len(listOrphanAgents()) != 0 {
		t.Fatal("expected empty list after dismiss")
	}
}

func TestOrphanAgentEviction(t *testing.T) {
	orphanAgentMu.Lock()
	orphanAgents = make(map[uint]*orphanAgentEntry)
	orphanAgentMu.Unlock()

	now := time.Now()
	for i := 0; i < orphanAgentMaxEntries+5; i++ {
		orphanAgentMu.Lock()
		if len(orphanAgents) >= orphanAgentMaxEntries {
			evictOldestOrphanLocked()
		}
		id := uint(i + 1)
		orphanAgents[id] = &orphanAgentEntry{
			clientIPs: map[string]struct{}{"1.1.1.1": {}},
			hitCount:  1,
			firstSeen: now,
			lastSeen:  now.Add(-time.Duration(i) * time.Second),
		}
		orphanAgentMu.Unlock()
	}

	if len(listOrphanAgents()) > orphanAgentMaxEntries {
		t.Fatalf("expected at most %d entries", orphanAgentMaxEntries)
	}
}
