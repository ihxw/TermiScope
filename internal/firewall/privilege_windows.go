//go:build windows

package firewall

import (
	"golang.org/x/sys/windows"
)

func isProcessPrivileged() bool {
	var token windows.Token
	err := windows.OpenProcessToken(windows.CurrentProcess(), windows.TOKEN_QUERY, &token)
	if err != nil {
		return false
	}
	defer token.Close()
	return token.IsElevated()
}

func defaultPrivilegeHint() string {
	return "Run TermiScope as Administrator (right-click → Run as administrator, or start the service from an elevated PowerShell)."
}
