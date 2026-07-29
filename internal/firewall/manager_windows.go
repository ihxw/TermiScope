//go:build windows

package firewall

// newPlatformManager returns the Windows netsh firewall manager.
func newPlatformManager() Manager {
	return newNetshManager()
}
