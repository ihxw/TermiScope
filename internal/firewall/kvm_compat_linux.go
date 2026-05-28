//go:build linux

package firewall

import (
	"fmt"
	"strings"
)

func (m *nftablesManager) KVMCompatibility() (KVMCompatStatus, error) {
	st := KVMCompatStatus{
		Bridges: libvirtBridgeNames(),
	}
	st.LibvirtActive = len(st.Bridges) > 0

	if v4, _, err := readIPForwardState(); err == nil {
		st.IPv4IPForward = v4
	}
	if commandExists("systemctl") {
		out, err := runCommand("systemctl", "is-active", "firewalld")
		st.FirewalldActive = err == nil && strings.TrimSpace(out) == "active"
	}
	if commandExists("ufw") {
		out, err := runCommand("ufw", "status")
		st.UFWActive = err == nil && strings.Contains(strings.ToLower(out), "status: active")
	}

	if st.LibvirtActive && m.tableExists() {
		st.TermiscopeLibvirtRules = m.hasLibvirtBridgeRules()
		st.TermiscopeForwardChain = m.hasForwardChain()
	}

	st.Recommendations = kvmRecommendations(st)
	return st, nil
}

func (m *nftablesManager) EnsureKVMCompatibility() error {
	if !libvirtNetworkingActive() {
		return nil
	}
	if err := m.ensureReady(); err != nil {
		return err
	}
	if err := ensureKernelIPForward("ipv4"); err != nil {
		return fmt.Errorf("ensure ipv4 forwarding for libvirt: %w", err)
	}
	if err := m.ensureLibvirtBridgeRules(); err != nil {
		return err
	}
	return m.ensureLibvirtForwardChain()
}

func (m *nftablesManager) hasLibvirtBridgeRules() bool {
	for _, bridge := range libvirtBridgeNames() {
		if !m.chainHasCommentInChain(nftChain, "termiscope-libvirt-in-"+bridge) {
			return false
		}
	}
	return len(libvirtBridgeNames()) > 0
}

func (m *nftablesManager) hasForwardChain() bool {
	out, err := runCommandPrivileged("nft", "list", "chain", nftFamily, nftTable, nftChainForward)
	return err == nil && strings.Contains(out, "hook forward")
}

func (m *nftablesManager) ensureLibvirtForwardChain() error {
	if !libvirtNetworkingActive() {
		return nil
	}
	if err := m.ensureForwardChain(); err != nil {
		return err
	}
	for _, bridge := range libvirtBridgeNames() {
		fwdComment := "termiscope-libvirt-fwd-" + bridge
		if m.chainHasCommentInChain(nftChainForward, fwdComment) {
			continue
		}
		_, err := runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChainForward,
			"iifname", bridge, "accept", "comment", nftCommentValue(fwdComment))
		if err != nil {
			return fmt.Errorf("add libvirt forward iif %s: %w", bridge, err)
		}
		fwdOutComment := "termiscope-libvirt-fwd-out-" + bridge
		if m.chainHasCommentInChain(nftChainForward, fwdOutComment) {
			continue
		}
		_, err = runCommandPrivileged("nft", "add", "rule", nftFamily, nftTable, nftChainForward,
			"oifname", bridge, "accept", "comment", nftCommentValue(fwdOutComment))
		if err != nil {
			return fmt.Errorf("add libvirt forward oif %s: %w", bridge, err)
		}
	}
	return nil
}


func kvmRecommendations(st KVMCompatStatus) []string {
	if !st.LibvirtActive {
		return nil
	}
	var rec []string
	if !st.IPv4IPForward {
		rec = append(rec, "enable_ipv4_forward")
	}
	if !st.FirewalldActive && !st.UFWActive {
		rec = append(rec, "start_firewalld_or_ufw")
	}
	if !st.TermiscopeLibvirtRules {
		rec = append(rec, "apply_termiscope_libvirt_rules")
	}
	if !st.TermiscopeForwardChain {
		rec = append(rec, "apply_termiscope_forward_chain")
	}
	// Only recommend a libvirt network restart when rules were missing and need to take effect.
	if !st.TermiscopeLibvirtRules || !st.TermiscopeForwardChain {
		rec = append(rec, "restart_libvirt_default_net")
	}
	return rec
}
