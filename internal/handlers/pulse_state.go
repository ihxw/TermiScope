package handlers

// monitorRecordSem limits concurrent async monitor_record writes under pulse load.
var monitorRecordSem = make(chan struct{}, 8)

func (h *MonitorHandler) cleanupHostPulseState(hostID uint) {
	h.saveMu.Lock()
	delete(h.lastDbSave, hostID)
	h.saveMu.Unlock()

	h.pulseMuGuard.Lock()
	delete(h.pulseMu, hostID)
	h.pulseMuGuard.Unlock()

	invalidatePulseHostCache(hostID)
}
