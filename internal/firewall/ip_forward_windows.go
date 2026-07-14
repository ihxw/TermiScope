//go:build windows

package firewall

import (
	"fmt"
	"strings"
)

func readWindowsIPForwardState() (ipv4, ipv6 bool, err error) {
	out, err := runCommand("netsh", "interface", "ipv4", "show", "config")
	if err == nil {
		ipv4 = strings.Contains(strings.ToLower(out), "forwarding") &&
			strings.Contains(strings.ToLower(out), "enabled")
	}

	out6, err6 := runCommand("netsh", "interface", "ipv6", "show", "global")
	if err6 == nil {
		lower := strings.ToLower(out6)
		ipv6 = strings.Contains(lower, "forwarding") && strings.Contains(lower, "enabled")
	}

	if err != nil && err6 != nil {
		return false, false, err
	}
	return ipv4, ipv6, nil
}

func setWindowsIPForward(ipVersion string, enabled bool) error {
	state := "disabled"
	if enabled {
		state = "enabled"
	}
	switch ipVersion {
	case "ipv4":
		_, err := runCommandPrivileged("netsh", "interface", "ipv4", "set", "global", "forwarding="+state)
		return err
	case "ipv6":
		_, err := runCommandPrivileged("netsh", "interface", "ipv6", "set", "global", "forwarding="+state)
		return err
	default:
		return fmt.Errorf("invalid ip version: %s", ipVersion)
	}
}

func (m *netshManager) GetPortForwardSettings() (PortForwardSettings, error) {
	persisted := loadPersistedPortForwardSettings()
	ipv4Forward, ipv6Forward, err := readWindowsIPForwardState()
	if err != nil {
		return PortForwardSettings{
			IPv4Enabled: persisted.IPv4Enabled,
			IPv6Enabled: persisted.IPv6Enabled,
		}, nil
	}
	return PortForwardSettings{
		IPv4Enabled:   persisted.IPv4Enabled,
		IPv6Enabled:   persisted.IPv6Enabled,
		IPv4IPForward: ipv4Forward,
		IPv6IPForward: ipv6Forward,
	}, nil
}

func (m *netshManager) UpdatePortForwardSettings(req UpdatePortForwardSettingsRequest) error {
	if req.IPv4Enabled {
		if err := setWindowsIPForward("ipv4", true); err != nil {
			return fmt.Errorf("enable ipv4 forwarding: %w", err)
		}
	} else {
		rules, _ := m.PortForwards()
		if !hasPortForwardFamily(rules, "ipv4") {
			if err := setWindowsIPForward("ipv4", false); err != nil {
				return fmt.Errorf("disable ipv4 forwarding: %w", err)
			}
		}
	}

	if req.IPv6Enabled {
		if err := setWindowsIPForward("ipv6", true); err != nil {
			return fmt.Errorf("enable ipv6 forwarding: %w", err)
		}
	} else {
		rules, _ := m.PortForwards()
		if !hasPortForwardFamily(rules, "ipv6") {
			if err := setWindowsIPForward("ipv6", false); err != nil {
				return fmt.Errorf("disable ipv6 forwarding: %w", err)
			}
		}
	}

	return savePersistedPortForwardSettings(persistedPortForwardSettings{
		IPv4Enabled: req.IPv4Enabled,
		IPv6Enabled: req.IPv6Enabled,
	})
}

func hasPortForwardFamily(rules []PortForwardRule, ipVersion string) bool {
	for _, rule := range rules {
		if rule.IPVersion == ipVersion {
			return true
		}
	}
	return false
}

func (m *netshManager) isPortForwardFamilyEnabled(ipVersion string) (bool, error) {
	settings, err := m.GetPortForwardSettings()
	if err != nil {
		return false, err
	}
	if ipVersion == "ipv6" {
		return settings.IPv6Enabled, nil
	}
	return settings.IPv4Enabled, nil
}
