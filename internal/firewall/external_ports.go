package firewall

import (
	"strconv"
	"strings"
)

// ExternalAccessPort describes a port with active or required external access.
type ExternalAccessPort struct {
	Port     string `json:"port"`
	Protocol string `json:"protocol"`
	RemoteIP string `json:"remote_ip,omitempty"`
	Label    string `json:"label,omitempty"`
	Required bool   `json:"required"`
}

// EnableAllowPort is selected by the user when enabling the firewall.
type EnableAllowPort struct {
	Port     string `json:"port"`
	Protocol string `json:"protocol"`
}

// EnableFirewallRequest configures ports to allow when enabling.
type EnableFirewallRequest struct {
	Allow []EnableAllowPort `json:"allow"`
}

func baselineExternalPorts() []ExternalAccessPort {
	seen := map[string]struct{}{}
	var out []ExternalAccessPort
	for _, port := range baselineAllowPorts() {
		key := port + "/tcp"
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, ExternalAccessPort{
			Port:     port,
			Protocol: "tcp",
			Required: true,
			Label:    "baseline",
		})
	}
	return out
}

func mergeExternalPorts(base []ExternalAccessPort, extra []ExternalAccessPort) []ExternalAccessPort {
	index := make(map[string]*ExternalAccessPort, len(base))
	order := make([]string, 0, len(base)+len(extra))
	for i := range base {
		key := base[i].Protocol + "/" + base[i].Port
		cp := base[i]
		index[key] = &cp
		order = append(order, key)
	}
	for _, item := range extra {
		key := item.Protocol + "/" + item.Port
		if existing, ok := index[key]; ok {
			if item.Required {
				existing.Required = true
			}
			if item.RemoteIP != "" && existing.RemoteIP == "" {
				existing.RemoteIP = item.RemoteIP
			}
			if item.Label != "" && existing.Label == "" {
				existing.Label = item.Label
			}
			continue
		}
		cp := item
		index[key] = &cp
		order = append(order, key)
	}
	out := make([]ExternalAccessPort, 0, len(order))
	for _, key := range order {
		out = append(out, *index[key])
	}
	return out
}

func markClientSessionPort(ports []ExternalAccessPort, clientIP string, listenPort int) []ExternalAccessPort {
	if clientIP == "" || listenPort < 1 {
		return ports
	}
	portStr := strconv.Itoa(listenPort)
	for i := range ports {
		if ports[i].Port == portStr && ports[i].Protocol == "tcp" {
			ports[i].Required = true
			ports[i].Label = "current_session"
			return ports
		}
	}
	return append(ports, ExternalAccessPort{
		Port:     portStr,
		Protocol: "tcp",
		RemoteIP: clientIP,
		Required: true,
		Label:    "current_session",
	})
}

func mergeEnableAllowWithBaseline(allow []EnableAllowPort) []EnableAllowPort {
	seen := map[string]struct{}{}
	var merged []EnableAllowPort
	add := func(port, protocol string) {
		port = strings.TrimSpace(port)
		protocol = strings.ToLower(strings.TrimSpace(protocol))
		if port == "" {
			return
		}
		if protocol == "" {
			protocol = "tcp"
		}
		key := protocol + "/" + port
		if _, ok := seen[key]; ok {
			return
		}
		seen[key] = struct{}{}
		merged = append(merged, EnableAllowPort{Port: port, Protocol: protocol})
	}
	for _, port := range baselineAllowPorts() {
		add(port, "tcp")
	}
	for _, item := range allow {
		add(item.Port, item.Protocol)
	}
	return merged
}
