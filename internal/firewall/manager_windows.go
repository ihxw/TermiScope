//go:build windows

package firewall

// NewManager returns the Windows netsh firewall manager.
func NewManager() Manager {
	return newNetshManager()
}
