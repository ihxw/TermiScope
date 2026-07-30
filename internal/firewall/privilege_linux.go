//go:build linux

package firewall

import (
	"os"
	"os/exec"
)

func isProcessPrivileged() bool {
	if os.Geteuid() == 0 {
		return true
	}
	if _, err := exec.LookPath("sudo"); err != nil {
		return false
	}
	return exec.Command("sudo", "-n", "true").Run() == nil
}

func defaultPrivilegeHint() string {
	return "Run TermiScope as root (e.g. systemd User=root) or configure passwordless sudo for nft, sysctl, and your package manager."
}
