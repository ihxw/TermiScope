package handlers

import (
	"sync"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

const agentHostCacheTTL = 2 * time.Minute

type cachedAgentHost struct {
	host    models.SSHHost
	expires time.Time
}

var (
	agentHostCache   = make(map[string]cachedAgentHost)
	agentHostCacheMu sync.RWMutex
)

func lookupAgentHostBySecret(db *gorm.DB, secret string) (*models.SSHHost, error) {
	now := time.Now()
	agentHostCacheMu.RLock()
	if entry, ok := agentHostCache[secret]; ok && now.Before(entry.expires) {
		host := entry.host
		agentHostCacheMu.RUnlock()
		return &host, nil
	}
	agentHostCacheMu.RUnlock()

	var host models.SSHHost
	if err := db.Where("monitor_secret = ? AND monitor_enabled = ?", secret, true).First(&host).Error; err != nil {
		return nil, err
	}

	agentHostCacheMu.Lock()
	agentHostCache[secret] = cachedAgentHost{host: host, expires: now.Add(agentHostCacheTTL)}
	agentHostCacheMu.Unlock()
	return &host, nil
}

func invalidateAgentHostCache(secret string) {
	if secret == "" {
		return
	}
	agentHostCacheMu.Lock()
	delete(agentHostCache, secret)
	agentHostCacheMu.Unlock()
}
