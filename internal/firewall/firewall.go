package firewall

import (
	"fmt"
	"net"
	"regexp"
	"strconv"
	"strings"
)

// defaultListenAddr returns the appropriate wildcard address for the given IP version
// when no explicit listen address is provided.
func defaultListenAddr(ipVersion string) string {
	if strings.EqualFold(ipVersion, "ipv6") {
		return "::"
	}
	return "0.0.0.0"
}

// Rule represents a single firewall rule entry.
type Rule struct {
	Number      int    `json:"number"`
	ID          string `json:"id,omitempty"`
	Managed     bool   `json:"managed,omitempty"`
	Action      string `json:"action"`
	Direction   string `json:"direction"`
	Protocol    string `json:"protocol"`
	Port        string `json:"port"`
	Source      string `json:"source"`
	Destination string `json:"destination"`
	Comment     string `json:"comment"`
	Raw         string `json:"raw"`
}

// Status describes firewall availability and state.
type Status struct {
	Available       bool                 `json:"available"`
	Enabled         bool                 `json:"enabled"`
	Backend         string               `json:"backend"`
	Message         string               `json:"message,omitempty"`
	PreviousBackend string               `json:"previous_backend,omitempty"`
	Migrated        bool                 `json:"migrated,omitempty"`
	Privileged      bool                 `json:"privileged"`
	PrivilegeHint   string               `json:"privilege_hint,omitempty"`
	Platform        string               `json:"platform,omitempty"`
	Persisted       bool                 `json:"persisted,omitempty"`
	BootLoaded      bool                 `json:"boot_loaded,omitempty"`
	PersistenceMsg  string               `json:"persistence_message,omitempty"`
	Warning         string               `json:"warning,omitempty"`
	Capabilities    FirewallCapabilities `json:"capabilities,omitempty"`
}

// FirewallCapabilities describes platform-specific firewall behavior for the UI.
type FirewallCapabilities struct {
	CanReject               bool `json:"can_reject"`
	CanPortForwardUDP       bool `json:"can_port_forward_udp"`
	CanSourcePortForward    bool `json:"can_source_port_forward"`
	GlobalDisable           bool `json:"global_disable"`
	ListsSystemRules        bool `json:"lists_system_rules"`
	SupportsKVMCompat       bool `json:"supports_kvm_compat"`
	SupportsBootPersistence bool `json:"supports_boot_persistence"`
}

// AddRuleRequest defines input for creating a rule.
type AddRuleRequest struct {
	Action    string `json:"action"`
	Port      string `json:"port"`
	Protocol  string `json:"protocol"`
	Source    string `json:"source"`
	Direction string `json:"direction"`
	Comment   string `json:"comment"`
}

// PortForwardRule represents a port forwarding (DNAT) entry.
type PortForwardRule struct {
	Number     int    `json:"number"`
	ID         string `json:"id,omitempty"`
	Managed    bool   `json:"managed,omitempty"`
	IPVersion  string `json:"ip_version"`
	Protocol   string `json:"protocol"`
	ListenPort string `json:"listen_port"`
	ListenAddr string `json:"listen_address,omitempty"`
	TargetIP   string `json:"target_ip"`
	TargetPort string `json:"target_port"`
	Source     string `json:"source,omitempty"`
	Comment    string `json:"comment"`
	Raw        string `json:"raw"`
}

// AddPortForwardRequest defines input for creating a port forward rule.
type AddPortForwardRequest struct {
	IPVersion  string `json:"ip_version"`
	Protocol   string `json:"protocol"`
	ListenPort string `json:"listen_port"`
	ListenAddr string `json:"listen_address"`
	TargetIP   string `json:"target_ip"`
	TargetPort string `json:"target_port"`
	Source     string `json:"source"`
	Comment    string `json:"comment"`
}

// Manager provides platform-specific firewall operations.
type Manager interface {
	Status() (Status, error)
	Rules() ([]Rule, error)
	AddRule(req AddRuleRequest) error
	UpdateRule(number int, req AddRuleRequest) error
	DeleteRule(number int) error
	PortForwards() ([]PortForwardRule, error)
	AddPortForward(req AddPortForwardRequest) error
	UpdatePortForward(number int, req AddPortForwardRequest) error
	DeletePortForward(number int) error
	GetPortForwardSettings() (PortForwardSettings, error)
	UpdatePortForwardSettings(req UpdatePortForwardSettingsRequest) error
	Enable(req EnableFirewallRequest) error
	Disable() error
	// Initialize prepares backend resources without enabling a default-deny policy (Linux nftables).
	Initialize() error
	ExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error)
	KVMCompatibility() (KVMCompatStatus, error)
	EnsureKVMCompatibility() error
}

var portPattern = regexp.MustCompile(`^\d{1,5}(:\d{1,5})?$`)

// ValidateAddRule checks user input before applying a rule.
func ValidateAddRule(req AddRuleRequest) error {
	action := strings.ToLower(strings.TrimSpace(req.Action))
	if action != "allow" && action != "deny" && action != "reject" {
		return fmt.Errorf("action must be allow, deny, or reject")
	}

	port := strings.TrimSpace(req.Port)
	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	if port == "" && protocol == "" {
		return fmt.Errorf("port or protocol is required")
	}

	if _, err := parsePortField(req.Port); err != nil {
		return err
	}

	switch protocol {
	case "", "tcp", "udp", "both", "tcp+udp", "tcpudp", "tcp/udp":
	default:
		return fmt.Errorf("protocol must be tcp, udp, both, or empty")
	}

	direction := normalizeDirection(req.Direction)
	if direction != "in" && direction != "out" {
		return fmt.Errorf("direction must be in or out")
	}

	source := sourceForRule(req.Source)
	if source != "any" {
		if strings.Contains(source, "/") {
			if _, _, err := net.ParseCIDR(source); err != nil {
				return fmt.Errorf("invalid source CIDR")
			}
		} else if ip := net.ParseIP(source); ip == nil {
			return fmt.Errorf("invalid source IP")
		}
	}
	req.Direction = direction

	comment := strings.TrimSpace(req.Comment)
	if len(comment) > 128 {
		return fmt.Errorf("comment too long (max 128 characters)")
	}

	return nil
}

// ValidateAddPortForward checks port forwarding input.
func ValidateAddPortForward(req AddPortForwardRequest) error {
	ipVersion := strings.ToLower(strings.TrimSpace(req.IPVersion))
	if ipVersion != "ipv4" && ipVersion != "ipv6" {
		return fmt.Errorf("ip_version must be ipv4 or ipv6")
	}

	protocol := strings.ToLower(strings.TrimSpace(req.Protocol))
	if protocol != "tcp" && protocol != "udp" {
		return fmt.Errorf("protocol must be tcp or udp")
	}

	listenPort := strings.TrimSpace(req.ListenPort)
	if listenPort == "" {
		return fmt.Errorf("listen_port is required")
	}
	if !portPattern.MatchString(listenPort) {
		return fmt.Errorf("invalid listen_port format")
	}
	if err := validatePortValue(listenPort); err != nil {
		return err
	}

	targetIP := strings.TrimSpace(req.TargetIP)
	if targetIP == "" {
		return fmt.Errorf("target_ip is required")
	}
	if strings.Contains(targetIP, "/") {
		return fmt.Errorf("target_ip must be a host address, not CIDR")
	}
	parsedIP := net.ParseIP(targetIP)
	if parsedIP == nil {
		return fmt.Errorf("invalid target_ip")
	}
	if ipVersion == "ipv4" && parsedIP.To4() == nil {
		return fmt.Errorf("target_ip must be an IPv4 address")
	}
	if ipVersion == "ipv6" && parsedIP.To4() != nil {
		return fmt.Errorf("target_ip must be an IPv6 address")
	}

	targetPort := strings.TrimSpace(req.TargetPort)
	if targetPort == "" {
		return fmt.Errorf("target_port is required")
	}
	if !portPattern.MatchString(targetPort) {
		return fmt.Errorf("invalid target_port format")
	}
	if err := validatePortValue(targetPort); err != nil {
		return err
	}

	listenAddr := strings.TrimSpace(req.ListenAddr)
	if listenAddr == "" {
		listenAddr = defaultListenAddr(ipVersion)
	}
	if ipVersion == "ipv4" {
		if listenAddr != "0.0.0.0" {
			if ip := net.ParseIP(listenAddr); ip == nil || ip.To4() == nil {
				return fmt.Errorf("listen_address must be an IPv4 address")
			}
		}
	} else if listenAddr != "::" {
		if ip := net.ParseIP(listenAddr); ip == nil || ip.To4() != nil {
			return fmt.Errorf("listen_address must be an IPv6 address")
		}
	}

	source := strings.TrimSpace(req.Source)
	if source != "" && source != "any" {
		if strings.Contains(source, "/") {
			ip, _, err := net.ParseCIDR(source)
			if err != nil {
				return fmt.Errorf("invalid source CIDR")
			}
			if ipVersion == "ipv4" && ip.To4() == nil {
				return fmt.Errorf("source CIDR must be IPv4")
			}
			if ipVersion == "ipv6" && ip.To4() != nil {
				return fmt.Errorf("source CIDR must be IPv6")
			}
		} else if ip := net.ParseIP(source); ip == nil {
			return fmt.Errorf("invalid source IP")
		} else if ipVersion == "ipv4" && ip.To4() == nil {
			return fmt.Errorf("source must be an IPv4 address")
		} else if ipVersion == "ipv6" && ip.To4() != nil {
			return fmt.Errorf("source must be an IPv6 address")
		}
	}

	comment := strings.TrimSpace(req.Comment)
	if len(comment) > 128 {
		return fmt.Errorf("comment too long (max 128 characters)")
	}

	return nil
}

func validatePortValue(port string) error {
	parts := strings.Split(port, ":")
	for _, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 65535 {
			return fmt.Errorf("port must be between 1 and 65535")
		}
	}
	return nil
}
