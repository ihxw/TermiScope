package ssh

import "strings"

// ResolveRemoteShell maps a host remote_shell and os_type to an SSH session start command.
// osType is "linux", "windows", or empty (treat powershell as Windows legacy default).
// useDefault true means the server default shell (session.Shell()) should be used.
func ResolveRemoteShell(remoteShell, osType string) (command string, useDefault bool) {
	shell := strings.ToLower(strings.TrimSpace(remoteShell))
	os := strings.ToLower(strings.TrimSpace(osType))

	switch shell {
	case "", "default":
		return "", true
	case "pwsh":
		return "pwsh -NoLogo", false
	case "powershell":
		if os == "linux" {
			return "pwsh -NoLogo", false
		}
		// windows or unspecified: Windows PowerShell 5.x (OpenSSH default on Windows Server)
		return "powershell.exe -NoLogo", false
	case "cmd":
		return "cmd.exe", false
	case "bash":
		return "bash -l", false
	default:
		return remoteShell, false
	}
}
