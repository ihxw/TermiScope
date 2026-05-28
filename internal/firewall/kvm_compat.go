package firewall

// KVMCompatStatus reports libvirt/KVM coexistence with TermiScope firewall.
type KVMCompatStatus struct {
	LibvirtActive          bool     `json:"libvirt_active"`
	Bridges                []string `json:"bridges,omitempty"`
	IPv4IPForward          bool     `json:"ipv4_ip_forward"`
	FirewalldActive        bool     `json:"firewalld_active"`
	UFWActive              bool     `json:"ufw_active"`
	TermiscopeLibvirtRules bool     `json:"termiscope_libvirt_rules"`
	TermiscopeForwardChain bool     `json:"termiscope_forward_chain"`
	Recommendations        []string `json:"recommendations,omitempty"`
}
