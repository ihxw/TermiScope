//go:build !linux && !windows

package firewall

// NewManager returns a stub manager on unsupported platforms.
func NewManager() Manager {
	return &stubManager{}
}
