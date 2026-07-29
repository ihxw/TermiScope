package handlers

import (
	"log"
	"sync"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

const (
	pulseHostCacheTTL    = 45 * time.Second
	pulseHostNegativeTTL = 10 * time.Minute
)

type pulseHostCacheEntry struct {
	host    models.SSHHost
	expires time.Time
}

type pulseHostNegativeEntry struct {
	expires time.Time
}

var (
	pulseHostCacheMu sync.RWMutex
	pulseHostCache   = make(map[uint]pulseHostCacheEntry)
	pulseHostMissing = make(map[uint]pulseHostNegativeEntry)
)

// lookupPulseHost returns a host row for pulse/auth paths, using a short-lived cache.
func lookupPulseHost(db *gorm.DB, hostID uint) (*models.SSHHost, error) {
	now := time.Now()

	pulseHostCacheMu.RLock()
	if neg, ok := pulseHostMissing[hostID]; ok && now.Before(neg.expires) {
		pulseHostCacheMu.RUnlock()
		return nil, gorm.ErrRecordNotFound
	}
	if entry, ok := pulseHostCache[hostID]; ok && now.Before(entry.expires) {
		host := entry.host
		pulseHostCacheMu.RUnlock()
		return &host, nil
	}
	pulseHostCacheMu.RUnlock()

	var host models.SSHHost
	if err := db.Select("*").First(&host, hostID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			pulseHostCacheMu.Lock()
			pulseHostMissing[hostID] = pulseHostNegativeEntry{expires: now.Add(pulseHostNegativeTTL)}
			delete(pulseHostCache, hostID)
			pulseHostCacheMu.Unlock()
		}
		return nil, err
	}

	pulseHostCacheMu.Lock()
	pulseHostCache[hostID] = pulseHostCacheEntry{host: host, expires: now.Add(pulseHostCacheTTL)}
	delete(pulseHostMissing, hostID)
	pulseHostCacheMu.Unlock()
	return &host, nil
}

func invalidatePulseHostCache(hostID uint) {
	pulseHostCacheMu.Lock()
	delete(pulseHostCache, hostID)
	delete(pulseHostMissing, hostID)
	pulseHostCacheMu.Unlock()
}

func refreshPulseHostCache(host models.SSHHost) {
	pulseHostCacheMu.Lock()
	pulseHostCache[host.ID] = pulseHostCacheEntry{host: host, expires: time.Now().Add(pulseHostCacheTTL)}
	delete(pulseHostMissing, host.ID)
	pulseHostCacheMu.Unlock()
}

var (
	orphanPulseLogMu   sync.Mutex
	orphanPulseLastLog = make(map[uint]time.Time)
)

func logOrphanPulseOnce(hostID uint) {
	orphanPulseLogMu.Lock()
	defer orphanPulseLogMu.Unlock()
	if t, ok := orphanPulseLastLog[hostID]; ok && time.Since(t) < time.Hour {
		return
	}
	orphanPulseLastLog[hostID] = time.Now()
	log.Printf("Monitor Pulse: host %d not found (orphan agent); further 404s suppressed for 1h", hostID)
}
