//go:build linux

package firewall

import (
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

const (
	nftTable            = "termiscope"
	nftChain            = "input"
	nftChainOutput      = "output"
	nftChainOutputNAT   = "output_nat"
	nftChainPrerouting  = "prerouting"
	nftChainPostrouting = "postrouting"
	nftChainForward     = "forward"
	nftFamily           = "inet"
)

type nftablesManager struct {
	mu              sync.Mutex
	ready           bool
	migrated        bool
	previousBackend string
	warnings        []string
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
				if err := m.addRuleInternal(ruleToAddRequest(rule)); err != nil {
					m.addWarning(fmt.Sprintf("failed to import %s rule %q: %v", exported.Backend, rule.Raw, err))
				}
			}
			m.migrated = true
			m.previousBackend = exported.Backend
			if err := writePrivilegedFile(m.migrationMarkerPath(), []byte(exported.Backend), 0644); err != nil {
				m.addWarning(fmt.Sprintf("failed to write migration marker: %v", err))
			}
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
				if err := m.addRuleInternal(ruleToAddRequest(rule)); err != nil {
					m.addWarning(fmt.Sprintf("failed to import %s rule %q: %v", exported.Backend, rule.Raw, err))
				}
			}
			m.migrated = true
			m.previousBackend = exported.Backend
			if err := writePrivilegedFile(m.migrationMarkerPath(), []byte(exported.Backend), 0644); err != nil {
				m.addWarning(fmt.Sprintf("failed to write migration marker: %v", err))
			}
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
		if err := m.ensureForwardChain(); err != nil {
			return err
		}
		if err := m.ensurePortForwardSupportRules(); err != nil {
			return err
		}
		if err := m.ensurePortForwardOutputRules(); err != nil {
			return err
		}
		if err := m.syncRouteLocalnetForPortForwards(); err != nil {
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

func (m *nftablesManager) addWarning(warning string) {
	warning = strings.TrimSpace(warning)
	if warning == "" {
		return
	}
	for _, existing := range m.warnings {
		if existing == warning {
			return
		}
	}
	m.warnings = append(m.warnings, warning)
}

func (m *nftablesManager) warningText() string {
	return strings.Join(m.warnings, "; ")
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
	if err := m.ensureForwardChain(); err != nil {
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
	_, err = runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChainPostrouting,
		"{ type nat hook postrouting priority srcnat; policy accept; }")
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}
	return m.ensureOutputNATChain()
}

func (m *nftablesManager) ensureOutputNATChain() error {
	_, err := runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChainOutputNAT,
		"{ type nat hook output priority dstnat; policy accept; }")
	if err != nil && !strings.Contains(err.Error(), "exists") {
		return err
	}
	return nil
}

func (m *nftablesManager) ensurePortForwardDNATAcceptRule() error {
	if m.chainHasComment("termiscope-pf-dnat") {
		return nil
	}
	_, err := runCommandPrivileged("nft", "insert", "rule", nftFamily, nftTable, nftChain,
		"ct", "status", "dnat", "accept", "comment", nftCommentValue("termiscope-pf-dnat"))
	if err != nil {
		return fmt.Errorf("add port forward dnat accept rule: %w", err)
	}
	return nil
}

func (m *nftablesManager) syncRouteLocalnetForPortForwards() error {
	rules, err := m.listPortForwards()
	if err != nil {
		return err
	}
	for _, rule := range rules {
		if rule.IPVersion == "ipv4" && isLoopbackTarget(rule.TargetIP) {
			return ensureRouteLocalnet()
		}
	}
	return nil
}

func (m *nftablesManager) ensureForwardChain() error {
	_, err := runCommandPrivileged("nft", "add", "chain", nftFamily, nftTable, nftChainForward,
		"{ type filter hook forward priority filter; policy accept; }")
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
		persisted, bootLoaded, persistenceMsg := nftPersistenceStatus()
		return finalizeStatus(Status{
			Available:       true,
			Enabled:         false,
			Backend:         "nftables",
			Migrated:        m.migrated,
			PreviousBackend: m.previousBackend,
			Message:         "not initialized; open firewall settings to import rules (default policy remains accept until you enable)",
			Persisted:       persisted,
			BootLoaded:      bootLoaded,
			PersistenceMsg:  persistenceMsg,
			Warning:         m.warningText(),
			Capabilities:    linuxFirewallCapabilities(),
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
		Available:    true,
		Enabled:      enabled,
		Backend:      "nftables",
		Migrated:     m.migrated,
		Capabilities: linuxFirewallCapabilities(),
		Warning:      m.warningText(),
	}
	status.Persisted, status.BootLoaded, status.PersistenceMsg = nftPersistenceStatus()
	if m.previousBackend != "" {
		status.PreviousBackend = m.previousBackend
	}
	return finalizeStatus(status), nil
}

func linuxFirewallCapabilities() FirewallCapabilities {
	return FirewallCapabilities{
		CanReject:               true,
		CanPortForwardUDP:       true,
		CanSourcePortForward:    true,
		GlobalDisable:           false,
		ListsSystemRules:        false,
		SupportsKVMCompat:       true,
		SupportsBootPersistence: true,
	}
}

var nftHandleRe = regexp.MustCompile(`# handle (\d+)`)
var nftCommentRe = regexp.MustCompile(`comment "([^"]*)"`)

func (m *nftablesManager) Rules() ([]Rule, error) {
	if !commandExists("nft") || !m.tableExists() {
		return []Rule{}, nil
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
			rule.ID = chain.name + ":" + nftRuleHandle(line)
			rule.Managed = true
			rule.Raw = line
			rules = append(rules, *rule)
		}
	}

	return rules, nil
}

func nftRuleHandle(line string) string {
	handleMatch := nftHandleRe.FindStringSubmatch(line)
	if len(handleMatch) != 2 {
		return ""
	}
	return handleMatch[1]
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
		err = m.persistRules()
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

func (m *nftablesManager) UpdateRule(number int, req AddRuleRequest) error {
	if err := m.ensureReady(); err != nil {
		return err
	}
	if number < 1 {
		return fmt.Errorf("invalid rule number")
	}
	if err := ValidateAddRule(req); err != nil {
		return err
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
	if err := m.deleteRuleByHandle(*target); err != nil {
		return err
	}
	if err := m.AddRule(req); err != nil {
		_ = m.addRuleInternal(ruleToAddRequest(*target))
		return err
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

	return m.deleteRuleByHandle(*target)
}

func (m *nftablesManager) deleteRuleByHandle(target Rule) error {
	handleMatch := nftHandleRe.FindStringSubmatch(target.Raw)
	if len(handleMatch) != 2 {
		return fmt.Errorf("cannot resolve rule handle")
	}

	chain := nftChain
	if normalizeDirection(target.Direction) == "out" {
		chain = nftChainOutput
	}
	_, err := runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, chain, "handle", handleMatch[1])
	if err == nil {
		err = m.persistRules()
	}
	return err
}

func (m *nftablesManager) enableInternal() error {
	_, _ = runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
		"iifname", "lo", "accept", "comment", nftCommentValue("termiscope-loopback"))
	_, err := runCommandPrivileged("nft", "chain", nftFamily, nftTable, nftChain, "{ policy drop; }")
	if err == nil {
		err = m.persistRules()
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
	if err := m.EnsureKVMCompatibility(); err != nil {
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
		err = m.persistRules()
	}
	return err
}

func (m *nftablesManager) persistRules() error {
	snippetPath := "/etc/nftables.d/termiscope.nft"
	out, err := runCommandPrivileged("nft", "list", "table", nftFamily, nftTable)
	if err != nil {
		return err
	}
	if err := writePrivilegedFile(snippetPath, []byte(out+"\n"), 0644); err != nil {
		return err
	}
	if err := ensureNFTBootPersistence(snippetPath); err != nil {
		return err
	}
	return nil
}

func (m *nftablesManager) PortForwards() ([]PortForwardRule, error) {
	if !commandExists("nft") || !m.tableExists() {
		return []PortForwardRule{}, nil
	}
	return m.listPortForwards()
}

func (m *nftablesManager) listPortForwards() ([]PortForwardRule, error) {
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
		rule.ID = nftChainPrerouting + ":" + nftRuleHandle(line)
		rule.Managed = true
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
		rule.TargetIP, rule.TargetPort = parseNftDNATTarget(m[1], rule.ListenPort)
	}

	if rule.Protocol == "" || rule.ListenPort == "" || rule.TargetIP == "" {
		return nil
	}
	if rule.TargetPort == "" {
		rule.TargetPort = rule.ListenPort
	}
	return rule
}

func parseNftDNATTarget(target, defaultPort string) (string, string) {
	target = strings.Trim(target, "\"")
	if strings.HasPrefix(target, "[") {
		if idx := strings.LastIndex(target, "]:"); idx >= 0 {
			return strings.TrimPrefix(target[:idx], "["), target[idx+2:]
		}
		return strings.Trim(target, "[]"), defaultPort
	}
	if idx := strings.LastIndex(target, ":"); idx >= 0 {
		return target[:idx], target[idx+1:]
	}
	return target, defaultPort
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

func (m *nftablesManager) ensurePortForwardSupportRules() error {
	rules, err := m.listPortForwards()
	if err != nil {
		return err
	}
	changed := false
	for _, rule := range rules {
		if err := m.ensurePortForwardSupportRule(rule, nftChainForward, "accept"); err != nil {
			return err
		}
		if err := m.ensurePortForwardSupportRule(rule, nftChainPostrouting, "masquerade"); err != nil {
			return err
		}
		changed = true
	}
	if changed {
		return m.persistRules()
	}
	return nil
}

func (m *nftablesManager) ensurePortForwardSupportRule(rule PortForwardRule, chain, action string) error {
	if m.chainHasCommentInChain(chain, portForwardSupportComment(rule)) {
		return nil
	}
	args, err := m.buildPortForwardSupportArgs(rule, action)
	if err != nil {
		return err
	}
	_, err = runCommandPrivileged("nft", append([]string{"add", "rule", nftFamily, nftTable, chain}, args...)...)
	return err
}

func (m *nftablesManager) buildPortForwardSupportArgs(rule PortForwardRule, action string) ([]string, error) {
	ipVersion := strings.ToLower(strings.TrimSpace(rule.IPVersion))
	protocol := strings.ToLower(strings.TrimSpace(rule.Protocol))
	targetIP := strings.TrimSpace(rule.TargetIP)
	targetPort := strings.TrimSpace(rule.TargetPort)
	source := strings.TrimSpace(rule.Source)
	if ipVersion != "ipv4" && ipVersion != "ipv6" {
		return nil, fmt.Errorf("invalid ip version: %s", ipVersion)
	}
	if protocol != "tcp" && protocol != "udp" {
		return nil, fmt.Errorf("invalid protocol: %s", protocol)
	}
	if targetIP == "" || targetPort == "" {
		return nil, fmt.Errorf("missing port forward target")
	}

	addrFamily := "ip"
	if ipVersion == "ipv6" {
		addrFamily = "ip6"
	}

	args := []string{"meta", "nfproto", ipVersion}
	if source != "" && source != "any" {
		args = append(args, addrFamily, "saddr", source)
	}
	args = append(args, addrFamily, "daddr", targetIP, protocol, "dport", targetPort, action)
	return append(args, "comment", nftCommentValue(portForwardSupportComment(rule))), nil
}

func portForwardSupportComment(rule PortForwardRule) string {
	listenAddr := strings.TrimSpace(rule.ListenAddr)
	if listenAddr == "" {
		if strings.EqualFold(rule.IPVersion, "ipv6") {
			listenAddr = "::"
		} else {
			listenAddr = "0.0.0.0"
		}
	}
	canonical := strings.Join([]string{
		strings.ToLower(strings.TrimSpace(rule.IPVersion)),
		strings.ToLower(strings.TrimSpace(rule.Protocol)),
		listenAddr,
		strings.TrimSpace(rule.ListenPort),
		strings.TrimSpace(rule.Source),
		strings.TrimSpace(rule.TargetIP),
		strings.TrimSpace(rule.TargetPort),
	}, "|")
	sum := sha1.Sum([]byte(canonical))
	return "termiscope-pf-" + hex.EncodeToString(sum[:])[:12]
}

func portForwardOutputComment(rule PortForwardRule) string {
	return portForwardSupportComment(rule) + "-out"
}

func (m *nftablesManager) buildPortForwardOutputNATArgs(req AddPortForwardRequest) ([]string, error) {
	args, err := m.buildPortForwardArgs(req)
	if err != nil {
		return nil, err
	}
	if len(args) >= 2 && args[len(args)-2] == "comment" {
		args = args[:len(args)-2]
	}
	rule := portForwardRuleFromRequest(req)
	return append(args, "comment", nftCommentValue(portForwardOutputComment(rule))), nil
}

func (m *nftablesManager) ensurePortForwardOutputNATRule(req AddPortForwardRequest) error {
	if err := m.ensureOutputNATChain(); err != nil {
		return err
	}
	rule := portForwardRuleFromRequest(req)
	if m.chainHasCommentInChain(nftChainOutputNAT, portForwardOutputComment(rule)) {
		return nil
	}
	args, err := m.buildPortForwardOutputNATArgs(req)
	if err != nil {
		return err
	}
	_, err = runCommandPrivileged("nft", append([]string{"add", "rule", nftFamily, nftTable, nftChainOutputNAT}, args...)...)
	return err
}

func (m *nftablesManager) ensurePortForwardOutputRules() error {
	rules, err := m.listPortForwards()
	if err != nil {
		return err
	}
	for _, rule := range rules {
		if err := m.ensurePortForwardOutputNATRule(portForwardRequestFromRule(rule)); err != nil {
			return err
		}
	}
	return nil
}

func (m *nftablesManager) deletePortForwardOutputNATRule(rule PortForwardRule) {
	comment := portForwardOutputComment(rule)
	out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, nftChainOutputNAT)
	if err != nil {
		return
	}
	needle := `comment "` + comment + `"`
	for _, line := range strings.Split(out, "\n") {
		if !strings.Contains(line, needle) {
			continue
		}
		handleMatch := nftHandleRe.FindStringSubmatch(line)
		if len(handleMatch) != 2 {
			continue
		}
		_, _ = runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, nftChainOutputNAT, "handle", handleMatch[1])
	}
}

func portForwardRuleFromRequest(req AddPortForwardRequest) PortForwardRule {
	ipVersion := strings.ToLower(strings.TrimSpace(req.IPVersion))
	listenAddr := strings.TrimSpace(req.ListenAddr)
	if listenAddr == "" {
		if ipVersion == "ipv6" {
			listenAddr = "::"
		} else {
			listenAddr = "0.0.0.0"
		}
	}
	return PortForwardRule{
		IPVersion:  ipVersion,
		Protocol:   strings.ToLower(strings.TrimSpace(req.Protocol)),
		ListenAddr: listenAddr,
		ListenPort: strings.TrimSpace(req.ListenPort),
		TargetIP:   strings.TrimSpace(req.TargetIP),
		TargetPort: strings.TrimSpace(req.TargetPort),
		Source:     strings.TrimSpace(req.Source),
	}
}

func (m *nftablesManager) addPortForwardInternal(req AddPortForwardRequest) error {
	dnatArgs, err := m.buildPortForwardArgs(req)
	if err != nil {
		return err
	}

	rule := portForwardRuleFromRequest(req)
	if rule.IPVersion == "ipv4" && isLoopbackTarget(rule.TargetIP) {
		if err := ensureRouteLocalnet(); err != nil {
			return fmt.Errorf("enable route_localnet for loopback target: %w", err)
		}
	}
	if err := m.ensurePortForwardDNATAcceptRule(); err != nil {
		return err
	}
	if err := m.ensureForwardChain(); err != nil {
		return err
	}
	if err := m.ensureNATChain(); err != nil {
		return err
	}

	forwardComment := portForwardSupportComment(rule)
	forwardExisted := m.chainHasCommentInChain(nftChainForward, forwardComment)
	if err := m.ensurePortForwardSupportRule(rule, nftChainForward, "accept"); err != nil {
		return err
	}
	masqueradeExisted := m.chainHasCommentInChain(nftChainPostrouting, forwardComment)
	if err := m.ensurePortForwardSupportRule(rule, nftChainPostrouting, "masquerade"); err != nil {
		if !forwardExisted {
			m.deletePortForwardSupportRuleInChain(rule, nftChainForward)
		}
		return err
	}
	outputExisted := m.chainHasCommentInChain(nftChainOutputNAT, portForwardOutputComment(rule))
	if err := m.ensurePortForwardOutputNATRule(req); err != nil {
		if !forwardExisted {
			m.deletePortForwardSupportRuleInChain(rule, nftChainForward)
		}
		if !masqueradeExisted {
			m.deletePortForwardSupportRuleInChain(rule, nftChainPostrouting)
		}
		return err
	}
	if _, err := runCommandPrivileged("nft", append([]string{"add", "rule", nftFamily, nftTable, nftChainPrerouting}, dnatArgs...)...); err != nil {
		if !forwardExisted {
			m.deletePortForwardSupportRuleInChain(rule, nftChainForward)
		}
		if !masqueradeExisted {
			m.deletePortForwardSupportRuleInChain(rule, nftChainPostrouting)
		}
		if !outputExisted {
			m.deletePortForwardOutputNATRule(rule)
		}
		return err
	}
	return m.persistRules()
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

func (m *nftablesManager) UpdatePortForward(number int, req AddPortForwardRequest) error {
	if err := m.ensureReady(); err != nil {
		return err
	}
	if number < 1 {
		return fmt.Errorf("invalid rule number")
	}
	if err := ValidateAddPortForward(req); err != nil {
		return err
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
	if err := m.deletePortForwardByHandle(*target); err != nil {
		return err
	}
	if err := m.AddPortForward(req); err != nil {
		_ = m.addPortForwardInternal(portForwardRequestFromRule(*target))
		return err
	}
	return nil
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

	return m.deletePortForwardByHandle(*target)
}

func (m *nftablesManager) deletePortForwardByHandle(target PortForwardRule) error {
	handleMatch := nftHandleRe.FindStringSubmatch(target.Raw)
	if len(handleMatch) != 2 {
		return fmt.Errorf("cannot resolve rule handle")
	}

	_, err := runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, nftChainPrerouting, "handle", handleMatch[1])
	if err == nil {
		m.deletePortForwardSupportRules(target)
		m.deletePortForwardOutputNATRule(target)
		if supportErr := m.ensurePortForwardSupportRules(); supportErr != nil {
			return supportErr
		}
		err = m.persistRules()
	}
	return err
}

func portForwardRequestFromRule(rule PortForwardRule) AddPortForwardRequest {
	return AddPortForwardRequest{
		IPVersion:  rule.IPVersion,
		Protocol:   rule.Protocol,
		ListenPort: rule.ListenPort,
		ListenAddr: rule.ListenAddr,
		TargetIP:   rule.TargetIP,
		TargetPort: rule.TargetPort,
		Source:     rule.Source,
		Comment:    rule.Comment,
	}
}

func (m *nftablesManager) deletePortForwardSupportRules(rule PortForwardRule) {
	for _, chain := range []string{nftChainForward, nftChainPostrouting} {
		m.deletePortForwardSupportRuleInChain(rule, chain)
	}
}

func (m *nftablesManager) deletePortForwardSupportRuleInChain(rule PortForwardRule, chain string) {
	comment := portForwardSupportComment(rule)
	out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, chain)
	if err != nil {
		return
	}
	needle := `comment "` + comment + `"`
	for _, line := range strings.Split(out, "\n") {
		if !strings.Contains(line, needle) {
			continue
		}
		handleMatch := nftHandleRe.FindStringSubmatch(line)
		if len(handleMatch) != 2 {
			continue
		}
		_, _ = runCommandPrivileged("nft", "delete", "rule", nftFamily, nftTable, chain, "handle", handleMatch[1])
	}
}
