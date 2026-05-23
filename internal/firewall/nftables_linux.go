//go:build linux

package firewall

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

const (
	nftTable           = "termiscope"
	nftChain           = "input"
	nftChainOutput     = "output"
	nftChainPrerouting = "prerouting"
	nftFamily          = "inet"
)

type nftablesManager struct {
	mu              sync.Mutex
	ready           bool
	migrated        bool
	previousBackend string
}

func newNftablesManager() Manager {
	return &nftablesManager{}
}

func (m *nftablesManager) migrationMarkerPath() string {
	return filepath.Join("/var/lib/termiscope", "firewall_migrated")
}

func (m *nftablesManager) tableExists() bool {
	out, err := runCommandPrivileged("nft", "list", "table", nftFamily, nftTable)
	if err != nil {
		return false
	}
	return strings.Contains(out, "table "+nftFamily+" "+nftTable)
}

func (m *nftablesManager) ensureReady() error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.ready && commandExists("nft") && m.tableExists() {
		return nil
	}

	if !commandExists("nft") {
		exported, err := exportExistingFirewall()
		if err != nil {
			return err
		}
		if exported.Backend != "" {
			m.previousBackend = exported.Backend
		}

		if err := installNftables(); err != nil {
			return err
		}

		if err := m.initTable(false); err != nil {
			return err
		}

		if exported.Backend != "" {
			for _, rule := range exported.Rules {
				_ = m.addRuleInternal(ruleToAddRequest(rule))
			}
			m.migrated = true
			m.previousBackend = exported.Backend
			_ = os.MkdirAll(filepath.Dir(m.migrationMarkerPath()), 0755)
			_ = os.WriteFile(m.migrationMarkerPath(), []byte(exported.Backend), 0644)
			// Do not disable ufw/firewalld or enable DROP here — that caused lockouts on upgrade.
			// Admin must explicitly enable the TermiScope firewall from system settings.
		}
	} else if !m.tableExists() {
		exported, _ := exportExistingFirewall()
		if err := m.initTable(false); err != nil {
			return err
		}
		if exported != nil && exported.Backend != "" {
			for _, rule := range exported.Rules {
				_ = m.addRuleInternal(ruleToAddRequest(rule))
			}
			m.migrated = true
			m.previousBackend = exported.Backend
			_ = os.MkdirAll(filepath.Dir(m.migrationMarkerPath()), 0755)
			_ = os.WriteFile(m.migrationMarkerPath(), []byte(exported.Backend), 0644)
		}
	}

	if !m.tableExists() {
		if err := m.initTable(false); err != nil {
			return err
		}
	} else {
		if err := m.ensureNATChain(); err != nil {
			return err
		}
		if err := m.ensureOutputChain(); err != nil {
			return err
		}
	}

	if data, err := os.ReadFile(m.migrationMarkerPath()); err == nil {
		m.migrated = true
		m.previousBackend = strings.TrimSpace(string(data))
	}

	m.ready = true
	return nil
}

func (m *nftablesManager) initTable(enabled bool) error {
	policy := "accept"
	if enabled {
		policy = "drop"
	}

	_, err := runCommandPrivileged("nft", "add", "table", nftFamily, nftTable)
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}

	chainSpec := fmt.Sprintf("{ type filter hook input priority filter; policy %s; }", policy)
	_, err = runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChain, chainSpec)
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}

	_, _ = runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
		"iifname", "lo", "accept", "comment", nftCommentValue("termiscope-loopback"))

	if err := m.ensureOutputChain(); err != nil {
		return err
	}
	return m.ensureNATChain()
}

func (m *nftablesManager) ensureOutputChain() error {
	_, err := runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChainOutput,
		"{ type filter hook output priority filter; policy accept; }")
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}
	return nil
}

func (m *nftablesManager) ensureNATChain() error {
	_, err := runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChainPrerouting,
		"{ type nat hook prerouting priority dstnat; policy accept; }")
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}
	return nil
}

func (m *nftablesManager) isEnabled() (bool, error) {
	out, err := runCommandPrivileged("nft", "list", "chain", nftFamily, nftTable, nftChain)
	if err != nil {
		return false, err
	}
	return strings.Contains(strings.ToLower(out), "policy drop"), nil
}

func (m *nftablesManager) Status() (Status, error) {
	if !isProcessPrivileged() {
		return finalizeStatus(Status{
			Available: false,
			Backend:   "nftables",
			Message:   "TermiScope process lacks privileges to manage nftables (need root or passwordless sudo)",
		}), nil
	}

	if !commandExists("nft") {
		return finalizeStatus(Status{
			Available: true,
			Enabled:   false,
			Backend:   "nftables",
			Message:   "nftables is not installed; open firewall settings to initialize",
		}), nil
	}

	if data, err := os.ReadFile(m.migrationMarkerPath()); err == nil {
		m.migrated = true
		m.previousBackend = strings.TrimSpace(string(data))
	}

	if !m.tableExists() {
		return finalizeStatus(Status{
			Available: true,
			Enabled:   false,
			Backend:   "nftables",
			Migrated:  m.migrated,
			PreviousBackend: m.previousBackend,
			Message:   "not initialized; open firewall settings to import rules (default policy remains accept until you enable)",
		}), nil
	}

	enabled, err := m.isEnabled()
	if err != nil {
		return finalizeStatus(Status{
			Available: true,
			Backend:   "nftables",
			Message:   err.Error(),
		}), nil
	}

	status := Status{
		Available: true,
		Enabled:   enabled,
		Backend:   "nftables",
		Migrated:  m.migrated,
	}
	if m.previousBackend != "" {
		status.PreviousBackend = m.previousBackend
	}
	return finalizeStatus(status), nil
}

var nftHandleRe = regexp.MustCompile(`# handle (\d+)`)
var nftCommentRe = regexp.MustCompile(`comment "([^"]*)"`)

func (m *nftablesManager) Rules() ([]Rule, error) {
	if err := m.ensureReady(); err != nil {
		return nil, err
	}

	var rules []Rule
	num := 0
	for _, chain := range []struct {
		name      string
		direction string
	}{
		{nftChain, "in"},
		{nftChainOutput, "out"},
	} {
		out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, chain.name)
		if err != nil {
			if chain.name == nftChainOutput {
				continue
			}
			return nil, err
		}
		for _, line := range strings.Split(out, "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "type filter hook") || strings.Contains(line, "policy ") {
				continue
			}
			if !strings.Contains(line, " handle ") {
				continue
			}

			rule := parseNftRuleLine(line)
			if rule == nil || rule.Comment == "termiscope-loopback" {
				continue
			}
			rule.Direction = chain.direction

			num++
			rule.Number = num
			rule.Raw = line
			rules = append(rules, *rule)
		}
	}

	return rules, nil
}

func parseNftRuleLine(line string) *Rule {
	lower := strings.ToLower(line)
	rule := &Rule{Direction: "in", Source: "any", Action: "allow"}

	switch {
	case strings.Contains(lower, " drop"):
		rule.Action = "deny"
	case strings.Contains(lower, " reject"):
		rule.Action = "reject"
	case strings.Contains(lower, " accept"):
		rule.Action = "allow"
	default:
		return nil
	}

	if m := nftCommentRe.FindStringSubmatch(line); len(m) == 2 {
		rule.Comment = m[1]
	}

	fields := strings.Fields(line)
	for i := 0; i < len(fields); i++ {
		switch fields[i] {
		case "tcp", "udp":
			rule.Protocol = fields[i]
		case "l4proto":
			if i+1 < len(fields) {
				rule.Protocol = strings.Trim(fields[i+1], ",\"")
			}
		case "dport":
			if i+1 < len(fields) {
				rule.Port = strings.Trim(fields[i+1], ",\"")
			}
		case "saddr":
			if i+1 < len(fields) {
				rule.Source = strings.Trim(fields[i+1], ",\"")
			}
		}
	}

	return rule
}

func (m *nftablesManager) buildRuleArgs(req AddRuleRequest) ([]string, error) {
	if err := ValidateAddRule(req); err != nil {
		return nil, err
	}

	source := sourceForRule(req.Source)
	port := strings.TrimSpace(req.Port)
	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	comment := strings.TrimSpace(req.Comment)

	var args []string

	if source != "any" {
		if strings.Contains(source, ":") {
			args = append(args, "ip6", "saddr", source)
		} else {
			args = append(args, "ip", "saddr", source)
		}
	}

	args = appendNFTProtocolPortMatch(args, protocol, port)

	switch strings.ToLower(strings.TrimSpace(req.Action)) {
	case "allow":
		args = append(args, "accept")
	case "deny":
		args = append(args, "drop")
	case "reject":
		args = append(args, "reject")
	}

	if comment != "" {
		args = append(args, "comment", nftCommentValue(comment))
	}

	if len(args) == 0 {
		return nil, fmt.Errorf("empty rule")
	}

	return args, nil
}

func (m *nftablesManager) ruleChain(req AddRuleRequest) string {
	if normalizeDirection(req.Direction) == "out" {
		return nftChainOutput
	}
	return nftChain
}

func (m *nftablesManager) addRuleInternal(req AddRuleRequest) error {
	args, err := m.buildRuleArgs(req)
	if err != nil {
		return err
	}
	chain := m.ruleChain(req)
	if chain == nftChainOutput {
		if err := m.ensureOutputChain(); err != nil {
			return err
		}
	}
	cmdArgs := append([]string{"add", "rule", nftFamily, nftTable, chain}, args...)
	_, err = runCommandPrivileged("nft", cmdArgs...)
	if err == nil {
		m.persistRules()
	}
	return err
}

func (m *nftablesManager) AddRule(req AddRuleRequest) error {
	if err := m.ensureReady(); err != nil {
		return err
	}
	reqs, err := ExpandAddRuleRequests(req)
	if err != nil {
		return err
	}
	for _, r := range reqs {
		if err := m.addRuleInternal(r); err != nil {
			return err
		}
	}
	return nil
}

func (m *nftablesManager) DeleteRule(number int) error {
	if err := m.ensureReady(); err != nil {
		return err
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
	if target == nil {
		return fmt.Errorf("rule not found")
	}

	handleMatch := nftHandleRe.FindStringSubmatch(target.Raw)
	if len(handleMatch) != 2 {
		return fmt.Errorf("cannot resolve rule handle")
	}

	chain := nftChain
	if normalizeDirection(target.Direction) == "out" {
		chain = nftChainOutput
	}
	_, err = runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, chain, "handle", handleMatch[1])
	if err == nil {
		m.persistRules()
	}
	return err
}

func (m *nftablesManager) enableInternal() error {
	_, _ = runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
		"iifname", "lo", "accept", "comment", nftCommentValue("termiscope-loopback"))
	_, err := runCommandPrivileged("nft", "chain", nftFamily, nftTable, nftChain, "{ policy drop; }")
	if err == nil {
		m.persistRules()
	}
	return err
}

func (m *nftablesManager) Initialize() error {
	return m.ensureReady()
}

func (m *nftablesManager) ExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	return detectExternalAccessPorts(clientIP)
}

func (m *nftablesManager) Enable(req EnableFirewallRequest) error {
	if err := m.ensureReady(); err != nil {
		return err
	}
	if err := m.ensureSafeBaselineRules(); err != nil {
		return err
	}
	if err := m.applyUserEnableAllowRules(req.Allow); err != nil {
		return err
	}
	if err := m.disablePreviousBackendOnEnable(); err != nil {
		return err
	}
	return m.enableInternal()
}

func (m *nftablesManager) Disable() error {
	if err := m.ensureReady(); err != nil {
		return err
	}
	_, err := runCommandPrivileged("nft", "chain", nftFamily, nftTable, nftChain, "{ policy accept; }")
	if err == nil {
		m.persistRules()
	}
	return err
}

func (m *nftablesManager) persistRules() {
	snippetPath := "/etc/nftables.d/termiscope.nft"
	out, err := runCommandPrivileged("nft", "list", "table", nftFamily, nftTable)
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(snippetPath), 0755)
	_ = os.WriteFile(snippetPath, []byte(out+"\n"), 0644)
}

func (m *nftablesManager) PortForwards() ([]PortForwardRule, error) {
	if err := m.ensureReady(); err != nil {
		return nil, err
	}

	out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, nftChainPrerouting)
	if err != nil {
		return nil, err
	}

	var rules []PortForwardRule
	num := 0
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.Contains(line, "type nat hook") || strings.Contains(line, "policy ") {
			continue
		}
		if !strings.Contains(strings.ToLower(line), " dnat ") || !strings.Contains(line, " handle ") {
			continue
		}

		rule := parseNftPortForwardLine(line)
		if rule == nil {
			continue
		}
		num++
		rule.Number = num
		rule.Raw = line
		rules = append(rules, *rule)
	}

	return rules, nil
}

var nftDnatTargetRe = regexp.MustCompile(`dnat(?:\s+ip6?)?\s+to\s+(\[?[^\s#]+)`)

func parseNftPortForwardLine(line string) *PortForwardRule {
	lower := strings.ToLower(line)
	if !strings.Contains(lower, " dnat ") {
		return nil
	}

	rule := &PortForwardRule{ListenAddr: "0.0.0.0", IPVersion: "ipv4"}
	if strings.Contains(lower, " nfproto ipv6") || strings.Contains(lower, " ip6 ") {
		rule.IPVersion = "ipv6"
		rule.ListenAddr = "::"
	}
	if m := nftCommentRe.FindStringSubmatch(line); len(m) == 2 {
		rule.Comment = m[1]
	}

	fields := strings.Fields(line)
	for i := 0; i < len(fields); i++ {
		switch fields[i] {
		case "tcp", "udp":
			rule.Protocol = fields[i]
		case "dport":
			if i+1 < len(fields) {
				rule.ListenPort = strings.Trim(fields[i+1], ",\"")
			}
		case "saddr":
			if i+1 < len(fields) {
				rule.Source = strings.Trim(fields[i+1], ",\"")
			}
		case "daddr":
			if i+1 < len(fields) {
				rule.ListenAddr = strings.Trim(fields[i+1], ",\"")
			}
		}
	}

	if m := nftDnatTargetRe.FindStringSubmatch(line); len(m) == 2 {
		target := strings.Trim(m[1], "\"[]")
		if idx := strings.LastIndex(target, ":"); idx >= 0 {
			rule.TargetIP = target[:idx]
			rule.TargetPort = target[idx+1:]
		} else {
			rule.TargetIP = target
			rule.TargetPort = rule.ListenPort
		}
	}

	if rule.Protocol == "" || rule.ListenPort == "" || rule.TargetIP == "" {
		return nil
	}
	if rule.TargetPort == "" {
		rule.TargetPort = rule.ListenPort
	}
	return rule
}

func (m *nftablesManager) buildPortForwardArgs(req AddPortForwardRequest) ([]string, error) {
	if err := ValidateAddPortForward(req); err != nil {
		return nil, err
	}

	ipVersion := strings.ToLower(strings.TrimSpace(req.IPVersion))
	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	listenPort := strings.TrimSpace(req.ListenPort)
	listenAddr := strings.TrimSpace(req.ListenAddr)
	targetIP := strings.TrimSpace(req.TargetIP)
	targetPort := strings.TrimSpace(req.TargetPort)
	source := strings.TrimSpace(req.Source)
	comment := strings.TrimSpace(req.Comment)

	if listenAddr == "" {
		if ipVersion == "ipv6" {
			listenAddr = "::"
		} else {
			listenAddr = "0.0.0.0"
		}
	}

	var args []string
	args = append(args, "meta", "nfproto", ipVersion)

	if listenAddr != "0.0.0.0" && listenAddr != "::" {
		if ipVersion == "ipv6" {
			args = append(args, "ip6", "daddr", listenAddr)
		} else {
			args = append(args, "ip", "daddr", listenAddr)
		}
	}

	if source != "" && source != "any" {
		if ipVersion == "ipv6" {
			args = append(args, "ip6", "saddr", source)
		} else {
			args = append(args, "ip", "saddr", source)
		}
	}

	args = append(args, protocol, "dport", listenPort)

	if ipVersion == "ipv6" {
		args = append(args, "dnat", "to", "["+targetIP+"]:"+targetPort)
	} else {
		args = append(args, "dnat", "to", targetIP+":"+targetPort)
	}

	if comment != "" {
		args = append(args, "comment", nftCommentValue(comment))
	}

	return args, nil
}

func (m *nftablesManager) addPortForwardInternal(req AddPortForwardRequest) error {
	args, err := m.buildPortForwardArgs(req)
	if err != nil {
		return err
	}
	cmdArgs := append([]string{"add", "rule", nftFamily, nftTable, nftChainPrerouting}, args...)
	_, err = runCommandPrivileged("nft", cmdArgs...)
	if err == nil {
		m.persistRules()
	}
	return err
}

func (m *nftablesManager) AddPortForward(req AddPortForwardRequest) error {
	if err := m.ensureReady(); err != nil {
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
	if err := ensureKernelIPForward(ipVersion); err != nil {
		return fmt.Errorf("enable kernel %s forwarding: %w", ipVersion, err)
	}
	return m.addPortForwardInternal(req)
}

func (m *nftablesManager) DeletePortForward(number int) error {
	if err := m.ensureReady(); err != nil {
		return err
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

	handleMatch := nftHandleRe.FindStringSubmatch(target.Raw)
	if len(handleMatch) != 2 {
		return fmt.Errorf("cannot resolve rule handle")
	}

	_, err = runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, nftChainPrerouting, "handle", handleMatch[1])
	if err == nil {
		m.persistRules()
	}
	return err
}
