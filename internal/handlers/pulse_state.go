package handlers

import (
	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// monitorRecordSem limits concurrent async monitor_record writes under pulse load.
var monitorRecordSem = make(chan struct{}, 8)

// prepareMonitorRedeploy starts a new agent timestamp epoch. A reinstalled host can
// report an older wall clock than the previous OS, which must not block all pulses.
func prepareMonitorRedeploy(db *gorm.DB, hostID uint) error {
	if err := db.Model(&models.SSHHost{}).
		Where("id = ?", hostID).
		Update("last_agent_timestamp", 0).Error; err != nil {
		return err
	}
	invalidatePulseHostCache(hostID)
	return nil
}

func (h *MonitorHandler) cleanupHostPulseState(hostID uint) {
	h.saveMu.Lock()
	delete(h.lastDbSave, hostID)
	h.saveMu.Unlock()

	h.pulseMuGuard.Lock()
	delete(h.pulseMu, hostID)
	h.pulseMuGuard.Unlock()

	invalidatePulseHostCache(hostID)
}
