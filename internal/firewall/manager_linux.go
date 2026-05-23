//go:build linux

package firewall

// NewManager returns the Linux nftables firewall manager.
func NewManager() Manager {
	return newNftablesManager()
}
