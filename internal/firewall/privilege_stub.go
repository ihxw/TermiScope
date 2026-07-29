//go:build !linux && !windows

package firewall

func isProcessPrivileged() bool {
	return false
}

func defaultPrivilegeHint() string {
	return "Firewall management is only supported when TermiScope runs on Linux or Windows with sufficient process privileges."
}
