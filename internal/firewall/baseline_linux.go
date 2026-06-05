//go:build linux

package firewall

import (
	"fmt"
	"os"
	"strings"
)

func (m *nftablesManager) chainHasCommentInChain(chain, comment string) bool {
	out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, chain)
	if err != nil {
		return false
	}
	needle := `comment "` + comment + `"`
	return strings.Contains(out, needle)
}

func (m *nftablesManager) chainHasCommentInTableChain(family, table, chain, comment string) bool {
	out, err := runCommandPrivileged("nft", "-a", "list", "chain", family, table, chain)
	if err != nil {
		return false
	}
	needle := `comment "` + comment + `"`
	return strings.Contains(out, needle)
}

// chainHasComment checks whether a comment exists on either input or output chain.
// Prefer chainHasCommentInChain when the target chain is known.
func (m *nftablesManager) chainHasComment(comment string) bool {
	return m.chainHasCommentInChain(nftChain, comment) || m.chainHasCommentInChain(nftChainOutput, comment)
}

// tableCommentSet returns the set of all comment values present in the entire nftables table.
// A single "nft list table" call is far cheaper than one "nft list chain" call per comment.
func (m *nftablesManager) tableCommentSet() map[string]struct{} {
	out, err := runCommandPrivileged("nft", "-a", "list", "table", nftFamily, nftTable)
	if err != nil {
		return nil
	}
	set := make(map[string]struct{})
	for _, line := range strings.Split(out, "\n") {
		matches := nftCommentRe.FindAllStringSubmatch(line, -1)
		for _, m := range matches {
			if len(m) == 2 {
				set[m[1]] = struct{}{}
			}
		}
	}
	return set
}

// ensureSafeBaselineRules adds rules that must exist before switching INPUT policy to drop.
func (m *nftablesManager) ensureSafeBaselineRules() error {
	// Fetch all existing comments in a single nft call to avoid N subprocess calls.
	if err := m.ensurePortForwardDNATAcceptRule(); err != nil {
		return err
	}

	existing := m.tableCommentSet()
	has := func(comment string) bool {
		if existing == nil {
			return m.chainHasCommentInChain(nftChain, comment)
		}
		_, ok := existing[comment]
		return ok
	}

	if !has("termiscope-established") {
		_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
			"ct", "state", "{", "established,", "related", "}", "accept", "comment", nftCommentValue("termiscope-established"))
		if err != nil {
			return fmt.Errorf("add established/related rule: %w", err)
		}
	}

	if !has("termiscope-loopback") {
		_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
			"iifname", "lo", "accept", "comment", nftCommentValue("termiscope-loopback"))
		if err != nil {
			return fmt.Errorf("add loopback rule: %w", err)
		}
	}

	if err := m.ensureLibvirtBridgeRules(); err != nil {
		return err
	}
	if err := m.ensureLibvirtForwardChain(); err != nil {
		return err
	}

	for _, port := range baselineAllowPorts() {
		comment := "termiscope-baseline-" + port
		if has(comment) {
			continue
		}
		if err := m.addRuleInternal(AddRuleRequest{
			Action:   "allow",
			Port:     port,
			Protocol: "tcp",
			Source:   "any",
			Comment:  comment,
		}); err != nil {
			return fmt.Errorf("add baseline allow tcp/%s: %w", port, err)
		}
	}
	return nil
}

// ensureLibvirtBridgeRules allows DHCP/DNS and host↔guest traffic on libvirt bridges (e.g. virbr0).
func (m *nftablesManager) ensureLibvirtBridgeRules() error {
	for _, bridge := range libvirtBridgeNames() {
		inComment := "termiscope-libvirt-in-" + bridge
		if !m.chainHasCommentInChain(nftChain, inComment) {
			_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
				"iifname", bridge, "accept", "comment", nftCommentValue(inComment))
			if err != nil {
				return fmt.Errorf("add libvirt input rule for %s: %w", bridge, err)
			}
		}
		outComment := "termiscope-libvirt-out-" + bridge
		if !m.chainHasCommentInChain(nftChainOutput, outComment) {
			if err := m.ensureOutputChain(); err != nil {
				return err
			}
			_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChainOutput,
				"oifname", bridge, "accept", "comment", nftCommentValue(outComment))
			if err != nil {
				return fmt.Errorf("add libvirt output rule for %s: %w", bridge, err)
			}
		}
	}
	return nil
}

func (m *nftablesManager) disablePreviousBackendOnEnable() error {
	backend := m.previousBackend
	if backend == "" {
		if data, err := os.ReadFile(m.migrationMarkerPath()); err == nil {
			backend = strings.TrimSpace(string(data))
		}
	}
	if backend == "" {
		return nil
	}
	return disablePreviousFirewall(backend)
}

func (m *nftablesManager) applyUserEnableAllowRules(allow []EnableAllowPort) error {
	for _, item := range allow {
		port := strings.TrimSpace(item.Port)
		if port == "" {
			continue
		}
		proto := strings.ToLower(strings.TrimSpace(item.Protocol))
		if proto == "" {
			proto = "tcp"
		}
		comment := fmt.Sprintf("termiscope-enable-%s-%s", proto, port)
		if m.chainHasCommentInChain(nftChain, comment) {
			continue
		}
		reqs, err := ExpandAddRuleRequests(AddRuleRequest{
			Action:    "allow",
			Port:      port,
			Protocol:  proto,
			Source:    "any",
			Direction: "in",
			Comment:   comment,
		})
		if err != nil {
			return err
		}
		for _, req := range reqs {
			if err := m.addRuleInternal(req); err != nil {
				return fmt.Errorf("add enable allow %s/%s: %w", proto, port, err)
			}
		}
	}
	return nil
}
