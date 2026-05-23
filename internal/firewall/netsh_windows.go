package firewall

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

type netshManager struct{}

func newNetshManager() Manager {
	return &netshManager{}
}

func (m *netshManager) run(args ...string) (string, error) {
	cmd := exec.Command("netsh", args...)
	out, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if text == "" {
			return "", fmt.Errorf("netsh command failed: %w", err)
		}
		return text, fmt.Errorf("%s", text)
	}
	return text, nil
}

func (m *netshManager) available() bool {
	_, err := exec.LookPath("netsh")
	return err == nil
}

func (m *netshManager) Status() (Status, error) {
	if !m.available() {
		return finalizeStatus(Status{
			Available: false,
			Backend:   "netsh",
			Message:   "netsh is not available",
		}), nil
	}

	if !isProcessPrivileged() {
		return finalizeStatus(Status{
			Available: false,
			Backend:   "netsh",
			Message:   "TermiScope must run as Administrator to manage Windows Firewall",
		}), nil
	}

	out, err := m.run("advfirewall", "show", "allprofiles", "state")
	if err != nil {
		return finalizeStatus(Status{
			Available: true,
			Backend:   "netsh",
			Message:   err.Error(),
		}), nil
	}

	enabled := strings.Contains(strings.ToLower(out), "state                                 on")
	return finalizeStatus(Status{
		Available: true,
		Enabled:   enabled,
		Backend:   "netsh",
	}), nil
}

var (
	netshRuleName  = regexp.MustCompile(`(?i)^Rule Name:\s*(.+)$`)
	netshEnabled   = regexp.MustCompile(`(?i)^Enabled:\s*(Yes|No)$`)
	netshDirection = regexp.MustCompile(`(?i)^Direction:\s*(In|Out)$`)
	netshAction    = regexp.MustCompile(`(?i)^Action:\s*(Allow|Block)$`)
	netshProtocol  = regexp.MustCompile(`(?i)^Protocol:\s*(.+)$`)
	netshLocalPort = regexp.MustCompile(`(?i)^LocalPort:\s*(.+)$`)
	netshRemoteIP  = regexp.MustCompile(`(?i)^RemoteIP:\s*(.+)$`)
)

func (m *netshManager) Rules() ([]Rule, error) {
	if !m.available() {
		return nil, fmt.Errorf("netsh is not available")
	}

	out, err := m.run("advfirewall", "firewall", "show", "rule", "name=all")
	if err != nil {
		return nil, err
	}

	var rules []Rule
	var current Rule
	number := 0

	flushRule := func() {
		if current.Raw == "" {
			return
		}
		number++
		current.Number = number
		rules = append(rules, current)
		current = Rule{}
	}

	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			flushRule()
			continue
		}

		if matches := netshRuleName.FindStringSubmatch(line); len(matches) == 2 {
			flushRule()
			current.Raw = line
			current.Comment = strings.TrimSpace(matches[1])
			continue
		}

		if current.Raw == "" {
			continue
		}
		current.Raw += "\n" + line

		if matches := netshEnabled.FindStringSubmatch(line); len(matches) == 2 {
			if strings.EqualFold(matches[1], "No") {
				current = Rule{}
			}
			continue
		}
		if matches := netshDirection.FindStringSubmatch(line); len(matches) == 2 {
			current.Direction = strings.ToLower(matches[1])
			continue
		}
		if matches := netshAction.FindStringSubmatch(line); len(matches) == 2 {
			current.Action = strings.ToLower(matches[1])
			if current.Action == "block" {
				current.Action = "deny"
			}
			continue
		}
		if matches := netshProtocol.FindStringSubmatch(line); len(matches) == 2 {
			proto := strings.ToLower(strings.TrimSpace(matches[1]))
			if proto != "any" {
				current.Protocol = proto
			}
			continue
		}
		if matches := netshLocalPort.FindStringSubmatch(line); len(matches) == 2 {
			port := strings.TrimSpace(matches[1])
			if port != "Any" {
				current.Port = port
			}
			continue
		}
		if matches := netshRemoteIP.FindStringSubmatch(line); len(matches) == 2 {
			source := strings.TrimSpace(matches[1])
			if source != "Any" {
				current.Source = source
			} else {
				current.Source = "any"
			}
		}
	}
	flushRule()

	return rules, nil
}

func (m *netshManager) AddRule(req AddRuleRequest) error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	reqs, err := ExpandAddRuleRequests(req)
	if err != nil {
		return err
	}
	for _, r := range reqs {
		if err := m.addRuleOnce(r); err != nil {
			return err
		}
	}
	return nil
}

func (m *netshManager) addRuleOnce(req AddRuleRequest) error {
	action := strings.ToLower(strings.TrimSpace(req.Action))
	port := strings.TrimSpace(req.Port)
	protocol := strings.ToUpper(strings.TrimSpace(req.Protocol))
	source := sourceForRule(req.Source)
	comment := strings.TrimSpace(req.Comment)

	ruleName := comment
	if ruleName == "" {
		ruleName = fmt.Sprintf("TermiScope-%s-%s", action, port)
		if port == "" {
			ruleName = fmt.Sprintf("TermiScope-%s", action)
		}
	}

	netshAction := "allow"
	if action == "deny" || action == "reject" {
		netshAction = "block"
	}

	dir := "in"
	if normalizeDirection(req.Direction) == "out" {
		dir = "out"
	}

	args := []string{
		"advfirewall", "firewall", "add", "rule",
		"name=" + ruleName,
		"dir=" + dir,
		"action=" + netshAction,
	}

	if protocol != "" {
		args = append(args, "protocol="+protocol)
	} else if port != "" {
		args = append(args, "protocol=TCP")
	}

	if port != "" {
		if strings.Contains(port, ",") {
			args = append(args, "localport="+port)
		} else {
			args = append(args, "localport="+port)
		}
	}

	if source != "any" {
		if dir == "in" {
			args = append(args, "remoteip="+source)
		} else {
			args = append(args, "remoteip="+source)
		}
	}

	_, err := m.run(args...)
	return err
}

func (m *netshManager) DeleteRule(number int) error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	if number < 1 {
		return fmt.Errorf("invalid rule number")
	}

	rules, err := m.Rules()
	if err != nil {
		return err
	}

	var target *Rule
	for i := range rules {
		if rules[i].Number == number {
			target = &rules[i]
			break
		}
	}
	if target == nil || target.Comment == "" {
		return fmt.Errorf("rule not found")
	}

	_, err = m.run("advfirewall", "firewall", "delete", "rule", "name="+target.Comment)
	return err
}

func (m *netshManager) ExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	return detectExternalAccessPorts(clientIP)
}

func (m *netshManager) Enable(req EnableFirewallRequest) error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	for _, item := range req.Allow {
		port := strings.TrimSpace(item.Port)
		if port == "" {
			continue
		}
		proto := strings.ToLower(strings.TrimSpace(item.Protocol))
		if proto == "" {
			proto = "tcp"
		}
		reqs, err := ExpandAddRuleRequests(AddRuleRequest{
			Action:    "allow",
			Port:      port,
			Protocol:  proto,
			Source:    "any",
			Direction: "in",
			Comment:   fmt.Sprintf("termiscope-enable-%s-%s", proto, port),
		})
		if err != nil {
			return err
		}
		for _, r := range reqs {
			if err := m.addRuleOnce(r); err != nil {
				return err
			}
		}
	}
	_, err := m.run("advfirewall", "set", "allprofiles", "state", "on")
	return err
}

func (m *netshManager) Disable() error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	_, err := m.run("advfirewall", "set", "allprofiles", "state", "off")
	return err
}

func (m *netshManager) Initialize() error {
	return nil
}

func (m *netshManager) PortForwards() ([]PortForwardRule, error) {
	if !m.available() {
		return nil, fmt.Errorf("netsh is not available")
	}

	out, err := m.run("interface", "portproxy", "show", "all")
	if err != nil {
		return nil, err
	}

	var rules []PortForwardRule
	num := 0
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(strings.ToLower(line), "listen") || strings.HasPrefix(line, "-") {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 5 {
			continue
		}

		num++
		ipVersion := "ipv4"
		if strings.Contains(fields[0], ":") {
			ipVersion = "ipv6"
		}
		rules = append(rules, PortForwardRule{
			Number:     num,
			IPVersion:  ipVersion,
			ListenAddr: fields[0],
			ListenPort: fields[1],
			TargetIP:   fields[3],
			TargetPort: fields[4],
			Protocol:   "tcp",
			Raw:        line,
		})
	}

	return rules, nil
}

func (m *netshManager) AddPortForward(req AddPortForwardRequest) error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	if err := ValidateAddPortForward(req); err != nil {
		return err
	}

	ipVersion := strings.ToLower(strings.TrimSpace(req.IPVersion))
	enabled, err := m.isPortForwardFamilyEnabled(ipVersion)
	if err != nil {
		return err
	}
	if !enabled {
		return fmt.Errorf("%s port forwarding is disabled; enable it in settings first", ipVersion)
	}
	if err := setWindowsIPForward(ipVersion, true); err != nil {
		return fmt.Errorf("enable kernel %s forwarding: %w", ipVersion, err)
	}

	listenAddr := strings.TrimSpace(req.ListenAddr)
	if listenAddr == "" {
		if ipVersion == "ipv6" {
			listenAddr = "::"
		} else {
			listenAddr = "0.0.0.0"
		}
	}

	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	if protocol == "udp" {
		return fmt.Errorf("udp port forwarding is not supported via netsh portproxy on Windows")
	}

	proxyType := "v4tov4"
	if ipVersion == "ipv6" {
		proxyType = "v6tov6"
	}

	_, err = m.run("interface", "portproxy", "add", proxyType,
		"listenaddress="+listenAddr,
		"listenport="+strings.TrimSpace(req.ListenPort),
		"connectaddress="+strings.TrimSpace(req.TargetIP),
		"connectport="+strings.TrimSpace(req.TargetPort))
	return err
}

func (m *netshManager) DeletePortForward(number int) error {
	if !m.available() {
		return fmt.Errorf("netsh is not available")
	}
	if number < 1 {
		return fmt.Errorf("invalid rule number")
	}

	rules, err := m.PortForwards()
	if err != nil {
		return err
	}

	var target *PortForwardRule
	for i := range rules {
		if rules[i].Number == number {
			target = &rules[i]
			break
		}
	}
	if target == nil {
		return fmt.Errorf("port forward rule not found")
	}

	proxyType := "v4tov4"
	if target.IPVersion == "ipv6" {
		proxyType = "v6tov6"
	}

	_, err = m.run("interface", "portproxy", "delete", proxyType,
		"listenaddress="+target.ListenAddr,
		"listenport="+target.ListenPort)
	return err
}
