package handlers

import (
	"os"
	"strings"
	"testing"
)

func TestWindowsInstallTemplateFallsBackWhenAgentConfigFlagIsMissing(t *testing.T) {
	content, err := os.ReadFile("../../scripts/install_agent.ps1.tmpl")
	if err != nil {
		t.Fatalf("read windows install template: %v", err)
	}
	script := string(content)

	for _, needle := range []string{
		`[Net.ServicePointManager]::SecurityProtocol`,
		`[Net.SecurityProtocolType]::Tls12`,
		`$DownloadUrl = "$ServerUrl/api/monitor/agent/termiscope-agent-windows-$RemoteArch.exe?host_id=$HostId"`,
		`Invoke-WebRequest -Uri $DownloadUrl -Headers @{ Authorization = "Bearer $Secret" } -UseBasicParsing -OutFile $TempPath`,
		`$PreviousErrorActionPreference = $ErrorActionPreference`,
		`$ErrorActionPreference = "Continue"`,
		`$AgentUsage = & $AgentPath -h 2>&1 | Out-String`,
		`$ErrorActionPreference = $PreviousErrorActionPreference`,
		`if ($AgentUsage -match "(?m)^\s+-config\b")`,
		"$InstallArgs = @(\"-config\", \"`\"$ConfigPath`\"\", \"-service\", \"install\")",
		`$InstallArgs = @("-server", $ServerUrl, "-secret", $Secret, "-id", $HostId, "-interval", "10s", "-service", "install")`,
	} {
		if !strings.Contains(script, needle) {
			t.Fatalf("windows install template missing %q:\n%s", needle, script)
		}
	}

	if strings.Contains(script, `$InstallArgs = "-config`) {
		t.Fatalf("windows install template still uses a single -config argument string:\n%s", script)
	}
}
