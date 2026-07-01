package firewall

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
)

// PortForwardSettings describes port forwarding feature toggles and kernel state.
type PortForwardSettings struct {
	IPv4Enabled   bool `json:"ipv4_enabled"`
	IPv6Enabled   bool `json:"ipv6_enabled"`
	IPv4IPForward bool `json:"ipv4_ip_forward"`
	IPv6IPForward bool `json:"ipv6_ip_forward"`
}

// UpdatePortForwardSettingsRequest updates port forwarding toggles.
type UpdatePortForwardSettingsRequest struct {
	IPv4Enabled bool `json:"ipv4_enabled"`
	IPv6Enabled bool `json:"ipv6_enabled"`
}

type persistedPortForwardSettings struct {
	IPv4Enabled bool `json:"ipv4_enabled"`
	IPv6Enabled bool `json:"ipv6_enabled"`
}

func portForwardSettingsPath() string {
	candidates := []string{
		"/var/lib/termiscope/port_forward_settings.json",
		filepath.Join(".", "data", "port_forward_settings.json"),
	}
	// Prefer the path where the settings file already exists.
	for _, p := range candidates {
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	// Fall back to the first candidate whose parent directory exists (for initial creation).
	for _, p := range candidates {
		dir := filepath.Dir(p)
		if dir == "." || dir == "" {
			continue
		}
		if _, err := os.Stat(dir); err == nil {
			return p
		}
	}
	return candidates[0]
}

func loadPersistedPortForwardSettings() persistedPortForwardSettings {
	settings := persistedPortForwardSettings{}
	data, err := os.ReadFile(portForwardSettingsPath())
	if err != nil {
		return settings
	}
	_ = json.Unmarshal(data, &settings)
	return settings
}

func savePersistedPortForwardSettings(settings persistedPortForwardSettings) error {
	path := portForwardSettingsPath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

func isIPv6Address(addr string) bool {
	addr = strings.TrimSpace(addr)
	if addr == "" || addr == "::" {
		return true
	}
	if strings.Contains(addr, ":") {
		return true
	}
	return false
}

func ipVersionOfAddress(addr string) string {
	if isIPv6Address(addr) {
		return "ipv6"
	}
	return "ipv4"
}
