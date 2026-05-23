//go:build linux

package firewall

import (
	"fmt"
	"strconv"
	"strings"
)

func readSysctlInt(key string) (bool, error) {
	out, err := runCommand("sysctl", "-n", key)
	if err != nil {
		return false, err
	}
	value := strings.TrimSpace(out)
	n, err := strconv.Atoi(value)
	if err != nil {
		return false, fmt.Errorf("invalid sysctl value for %s: %s", key, value)
	}
	return n != 0, nil
}

func setSysctlInt(key string, enabled bool) error {
	value := "0"
	if enabled {
		value = "1"
	}
	_, err := runCommandPrivileged("sysctl", "-w", key+"="+value)
	return err
}

func readIPForwardState() (ipv4, ipv6 bool, err error) {
	ipv4, err = readSysctlInt("net.ipv4.ip_forward")
	if err != nil {
		return false, false, err
	}
	ipv6, err = readSysctlInt("net.ipv6.conf.all.forwarding")
	if err != nil {
		return ipv4, false, err
	}
	return ipv4, ipv6, nil
}

func ensureKernelIPForward(ipVersion string) error {
	switch ipVersion {
	case "ipv4":
		enabled, err := readSysctlInt("net.ipv4.ip_forward")
		if err != nil {
			return err
		}
		if !enabled {
			return setSysctlInt("net.ipv4.ip_forward", true)
		}
	case "ipv6":
		enabled, err := readSysctlInt("net.ipv6.conf.all.forwarding")
		if err != nil {
			return err
		}
		if !enabled {
			if err := setSysctlInt("net.ipv6.conf.all.forwarding", true); err != nil {
				return err
			}
			_ = setSysctlInt("net.ipv6.conf.default.forwarding", true)
		}
	default:
		return fmt.Errorf("invalid ip version: %s", ipVersion)
	}
	return nil
}

func maybeDisableKernelIPForward(ipVersion string, rules []PortForwardRule) error {
	for _, rule := range rules {
		if rule.IPVersion == ipVersion {
			return nil
		}
	}
	switch ipVersion {
	case "ipv4":
		return setSysctlInt("net.ipv4.ip_forward", false)
	case "ipv6":
		if err := setSysctlInt("net.ipv6.conf.all.forwarding", false); err != nil {
			return err
		}
		_ = setSysctlInt("net.ipv6.conf.default.forwarding", false)
	}
	return nil
}

func (m *nftablesManager) GetPortForwardSettings() (PortForwardSettings, error) {
	persisted := loadPersistedPortForwardSettings()
	ipv4Forward, ipv6Forward, err := readIPForwardState()
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

func (m *nftablesManager) UpdatePortForwardSettings(req UpdatePortForwardSettingsRequest) error {
	if err := m.ensureReady(); err != nil {
		return err
	}

	persisted := persistedPortForwardSettings{
		IPv4Enabled: req.IPv4Enabled,
		IPv6Enabled: req.IPv6Enabled,
	}

	if req.IPv4Enabled {
		if err := ensureKernelIPForward("ipv4"); err != nil {
			return fmt.Errorf("enable ipv4 forwarding: %w", err)
		}
	} else {
		rules, _ := m.PortForwards()
		if err := maybeDisableKernelIPForward("ipv4", rules); err != nil {
			return fmt.Errorf("disable ipv4 forwarding: %w", err)
		}
	}

	if req.IPv6Enabled {
		if err := ensureKernelIPForward("ipv6"); err != nil {
			return fmt.Errorf("enable ipv6 forwarding: %w", err)
		}
	} else {
		rules, _ := m.PortForwards()
		if err := maybeDisableKernelIPForward("ipv6", rules); err != nil {
			return fmt.Errorf("disable ipv6 forwarding: %w", err)
		}
	}

	return savePersistedPortForwardSettings(persisted)
}

func (m *nftablesManager) isPortForwardFamilyEnabled(ipVersion string) (bool, error) {
	settings, err := m.GetPortForwardSettings()
	if err != nil {
		return false, err
	}
	if ipVersion == "ipv6" {
		return settings.IPv6Enabled, nil
	}
	return settings.IPv4Enabled, nil
}
