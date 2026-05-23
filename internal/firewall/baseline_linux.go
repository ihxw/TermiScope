//go:build linux

package firewall

import (
	"fmt"
	"os"
	"strings"
)

func (m *nftablesManager) chainHasComment(comment string) bool {
	needle := `comment "` + comment + `"`
	for _, chain := range []string{nftChain, nftChainOutput} {
		out, err := runCommandPrivileged("nft", "-a", "list", "chain", nftFamily, nftTable, chain)
		if err != nil {
			continue
		}
		if strings.Contains(out, needle) {
			return true
		}
	}
	return false
}

// ensureSafeBaselineRules adds rules that must exist before switching INPUT policy to drop.
func (m *nftablesManager) ensureSafeBaselineRules() error {
	if !m.chainHasComment("termiscope-established") {
		_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
			"ct", "state", "{", "established,", "related", "}", "accept", "comment", nftCommentValue("termiscope-established"))
		if err != nil {
			return fmt.Errorf("add established/related rule: %w", err)
		}
	}

	if !m.chainHasComment("termiscope-loopback") {
		_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChain,
			"iifname", "lo", "accept", "comment", nftCommentValue("termiscope-loopback"))
		if err != nil {
			return fmt.Errorf("add loopback rule: %w", err)
		}
	}

	for _, port := range baselineAllowPorts() {
		comment := "termiscope-baseline-" + port
		if m.chainHasComment(comment) {
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
		if m.chainHasComment(comment) {
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
