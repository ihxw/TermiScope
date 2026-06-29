import re

with open('internal/handlers/monitor.go', 'r') as f:
    content = f.read()

# 1. Replace single Deploy Setup Directory
old_setup1 = """	// 2. Setup Directory
	session, _ = client.NewSession()
	setupCmd := "mkdir -p /opt/termiscope/agent"
	if host.Username != "root" {
		setupCmd = "sudo -S mkdir -p /opt/termiscope/agent"
		session.Stdin = strings.NewReader(password + "\\n")
	}
	if out, err := session.CombinedOutput(setupCmd); err != nil {
		log.Printf("Monitor Deploy: Setup dir failed: %v, Out: %s", err, string(out))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create directory: " + string(out)})
		return
	}
	session.Close()

	// 3. Upload Binary
	remoteBinaryPath := "/opt/termiscope/agent/termiscope-agent\""""

new_setup1 = """	// 2. Setup Directory
	session, _ = client.NewSession()
	setupScript := `
for dir in "/opt" "/usr/local" "/var/lib" "/tmp"; do
	if mkdir -p "$dir/termiscope/agent" 2>/dev/null && touch "$dir/termiscope/agent/.test" 2>/dev/null; then
		rm -f "$dir/termiscope/agent/.test"
		echo "$dir/termiscope/agent"
		exit 0
	fi
done
exit 1
`
	setupCmd := fmt.Sprintf("sh -c '%s'", setupScript)
	if host.Username != "root" {
		setupCmd = fmt.Sprintf("sudo -S sh -c '%s'", setupScript)
		session.Stdin = strings.NewReader(password + "\\n")
	}
	out, err := session.CombinedOutput(setupCmd)
	if err != nil {
		log.Printf("Monitor Deploy: Setup dir failed: %v, Out: %s", err, string(out))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to find writable directory: " + string(out)})
		return
	}
	installDir := strings.TrimSpace(string(out))
	if installDir == "" {
		installDir = "/opt/termiscope/agent"
	}
	session.Close()

	// 3. Upload Binary
	remoteBinaryPath := fmt.Sprintf("%s/termiscope-agent", installDir)"""

content = content.replace(old_setup1, new_setup1)

# 2. Replace batch deployToHost Setup Directory
old_setup2 = """	// Setup Directory
	session, _ = client.NewSession()
	setupCmd := "mkdir -p /opt/termiscope/agent"
	if host.Username != "root" {
		setupCmd = "sudo -S mkdir -p /opt/termiscope/agent"
		session.Stdin = strings.NewReader(password + "\\n")
	}
	if out, err := session.CombinedOutput(setupCmd); err != nil {
		return fmt.Errorf("创建目录失败: %s", string(out))
	}
	session.Close()

	// Upload Binary
	remoteBinaryPath := "/opt/termiscope/agent/termiscope-agent\""""

new_setup2 = """	// Setup Directory
	session, _ = client.NewSession()
	setupScript := `
for dir in "/opt" "/usr/local" "/var/lib" "/tmp"; do
	if mkdir -p "$dir/termiscope/agent" 2>/dev/null && touch "$dir/termiscope/agent/.test" 2>/dev/null; then
		rm -f "$dir/termiscope/agent/.test"
		echo "$dir/termiscope/agent"
		exit 0
	fi
done
exit 1
`
	setupCmd := fmt.Sprintf("sh -c '%s'", setupScript)
	if host.Username != "root" {
		setupCmd = fmt.Sprintf("sudo -S sh -c '%s'", setupScript)
		session.Stdin = strings.NewReader(password + "\\n")
	}
	out, err := session.CombinedOutput(setupCmd)
	if err != nil {
		return fmt.Errorf("创建目录失败: %s", string(out))
	}
	installDir := strings.TrimSpace(string(out))
	if installDir == "" {
		installDir = "/opt/termiscope/agent"
	}
	session.Close()

	// Upload Binary
	remoteBinaryPath := fmt.Sprintf("%s/termiscope-agent", installDir)"""

content = content.replace(old_setup2, new_setup2)

# 3. Replace systemd config in Deploy
old_sysd1 = """ExecStart=%s
Restart=always
User=root
WorkingDirectory=/opt/termiscope/agent

[Install]
WantedBy=multi-user.target
`, execCmd)"""

new_sysd1 = """ExecStart=%s
Restart=always
User=root
WorkingDirectory=%s

[Install]
WantedBy=multi-user.target
`, execCmd, installDir)"""

content = content.replace(old_sysd1, new_sysd1)

# 4. Remove uninstall hardcoded path
old_uninstall = """	cmd := "systemctl disable --now termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload && rm -rf /opt/termiscope/agent"
	if host.Username != "root" {
		cmd = "sudo -S systemctl disable --now termiscope-agent && sudo -S rm -f /etc/systemd/system/termiscope-agent.service && sudo -S systemctl daemon-reload && sudo -S rm -rf /opt/termiscope/agent"
"""

new_uninstall = """	cmd := "systemctl disable --now termiscope-agent && rm -f /etc/systemd/system/termiscope-agent.service && systemctl daemon-reload && for dir in /opt /usr/local /var/lib /tmp; do rm -rf $dir/termiscope/agent; done"
	if host.Username != "root" {
		cmd = "sudo -S systemctl disable --now termiscope-agent && sudo -S rm -f /etc/systemd/system/termiscope-agent.service && sudo -S systemctl daemon-reload && for dir in /opt /usr/local /var/lib /tmp; do sudo -S rm -rf $dir/termiscope/agent; done"
"""

content = content.replace(old_uninstall, new_uninstall)

with open('internal/handlers/monitor.go', 'w') as f:
    f.write(content)

