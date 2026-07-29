package monitor

import "sync"

var (
	hostRemovedMu        sync.RWMutex
	hostRemovedCallbacks []func(hostID uint)
)

// OnHostRemoved registers a callback when a host is removed from the hub.
func OnHostRemoved(fn func(hostID uint)) {
	hostRemovedMu.Lock()
	hostRemovedCallbacks = append(hostRemovedCallbacks, fn)
	hostRemovedMu.Unlock()
}

func notifyHostRemoved(hostID uint) {
	hostRemovedMu.RLock()
	cbs := hostRemovedCallbacks
	hostRemovedMu.RUnlock()
	for _, fn := range cbs {
		fn(hostID)
	}
}
