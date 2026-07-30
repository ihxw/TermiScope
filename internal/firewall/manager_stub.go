//go:build !linux && !windows

package firewall

// newPlatformManager returns a stub manager on unsupported platforms.
func newPlatformManager() Manager {
	return &stubManager{}
}
