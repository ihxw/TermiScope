//go:build linux

package firewall

// newPlatformManager returns the Linux nftables firewall manager.
func newPlatformManager() Manager {
	return newNftablesManager()
}
