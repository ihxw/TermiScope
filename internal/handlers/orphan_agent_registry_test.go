package handlers

import (
	"testing"
	"time"
)

func TestRecordAndListOrphanAgents(t *testing.T) {
	orphanAgentMu.Lock()
	orphanAgents = make(map[uint]*orphanAgentEntry)
	orphanAgentMu.Unlock()

	recordOrphanPulse(21, "1.2.3.4", "host-a", "00:11:22:33:44:55")
	recordOrphanPulse(21, "5.6.7.8", "host-b", "66:77:88:99:aa:bb")

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
	if len(list[0].Hostnames) != 2 {
		t.Fatalf("expected 2 hostnames, got %v", list[0].Hostnames)
	}
	if len(list[0].Macs) != 2 {
		t.Fatalf("expected 2 MACs, got %v", list[0].Macs)
	}

	dismissOrphanAgent(21)
	if len(listOrphanAgents()) != 0 {
		t.Fatal("expected empty list after dismiss")
	}
}

func TestClearOrphanPulse(t *testing.T) {
	orphanAgentMu.Lock()
	orphanAgents = make(map[uint]*orphanAgentEntry)
	orphanAgentMu.Unlock()

	recordOrphanPulse(42, "10.0.0.1", "host-c", "00:aa:bb:cc:dd:ee")
	if len(listOrphanAgents()) != 1 {
		t.Fatal("expected 1 orphan after record")
	}
	clearOrphanPulse(42)
	if len(listOrphanAgents()) != 0 {
		t.Fatal("expected entry to be cleared after clearOrphanPulse")
	}
}

func TestRecordOrphanIgnoresZero(t *testing.T) {
	orphanAgentMu.Lock()
	orphanAgents = make(map[uint]*orphanAgentEntry)
	orphanAgentMu.Unlock()

	recordOrphanPulse(0, "10.0.0.1", "host-d", "00:ff:ee:dd:cc:bb")
	if len(listOrphanAgents()) != 0 {
		t.Fatal("expected host_id 0 to be ignored")
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
