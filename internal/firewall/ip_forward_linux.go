//go:build linux

package firewall

import (
	"fmt"
	"net"
	"path/filepath"
	"strconv"
	"strings"
)

const sysctlPersistPath = "/etc/sysctl.d/99-termiscope-forward.conf"

// sysctl keys managed by TermiScope; kept centralised so the persisted file always reflects the
// full intent (avoiding stale entries when toggles flip).
var managedForwardSysctls = []string{
	"net.ipv4.ip_forward",
	"net.ipv6.conf.all.forwarding",
	"net.ipv6.conf.default.forwarding",
}

func isLoopbackTarget(ip string) bool {
	parsed := net.ParseIP(strings.TrimSpace(ip))
	return parsed != nil && parsed.IsLoopback()
}

func ensureRouteLocalnet() error {
	matches, err := filepath.Glob("/proc/sys/net/ipv4/conf/*/route_localnet")
	if err != nil {
		return err
	}
	for _, match := range matches {
		parts := strings.Split(match, "/")
		if len(parts) < 6 {
			continue
		}
		iface := parts[5]
		key := fmt.Sprintf("net.ipv4.conf.%s.route_localnet", iface)
		enabled, err := readSysctlInt(key)
		if err != nil {
			continue
		}
		if !enabled {
			if err := setSysctlInt(key, true); err != nil {
				return err
			}
		}
	}
	return nil
}

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
	if _, err := runCommandPrivileged("sysctl", "-w", key+"="+value); err != nil {
		return err
	}
	return persistManagedForwardSysctls()
}

// persistManagedForwardSysctls writes the current runtime values of TermiScope-managed
// forwarding sysctls to /etc/sysctl.d so they survive reboot. Errors are returned so callers can
// surface them, but a missing /etc/sysctl.d falls back gracefully (no persistence).
func persistManagedForwardSysctls() error {
	var lines []string
	lines = append(lines, "# Managed by TermiScope. Do not edit by hand.")
	for _, key := range managedForwardSysctls {
		val, err := readSysctlInt(key)
		if err != nil {
			// Skip unreadable keys (e.g. IPv6 disabled) instead of aborting persistence entirely.
			continue
		}
		v := "0"
		if val {
			v = "1"
		}
		lines = append(lines, fmt.Sprintf("%s = %s", key, v))
	}

	// Also persist any route_localnet sysctls that are currently enabled
	if matches, err := filepath.Glob("/proc/sys/net/ipv4/conf/*/route_localnet"); err == nil {
		for _, match := range matches {
			parts := strings.Split(match, "/")
			if len(parts) >= 6 {
				iface := parts[5]
				key := fmt.Sprintf("net.ipv4.conf.%s.route_localnet", iface)
				val, err := readSysctlInt(key)
				if err == nil && val {
					lines = append(lines, fmt.Sprintf("%s = 1", key))
				}
			}
		}
	}

	content := strings.Join(lines, "\n") + "\n"
	return writePrivilegedFile(sysctlPersistPath, []byte(content), 0644)
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
	// KVM/libvirt NAT requires ip_forward even when TermiScope port forwarding is off.
	if libvirtNetworkingActive() {
		return nil
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
		if err := m.removePortForwardFamilyRules("ipv4"); err != nil {
			return fmt.Errorf("remove ipv4 port forward rules: %w", err)
		}
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
		if err := m.removePortForwardFamilyRules("ipv6"); err != nil {
			return fmt.Errorf("remove ipv6 port forward rules: %w", err)
		}
		rules, _ := m.PortForwards()
		if err := maybeDisableKernelIPForward("ipv6", rules); err != nil {
			return fmt.Errorf("disable ipv6 forwarding: %w", err)
		}
	}

	return savePersistedPortForwardSettings(persisted)
}

// removePortForwardFamilyRules deletes every prerouting DNAT rule (and its forward / postrouting /
// output_nat support rules) that belongs to the given IP version, so toggling the family off truly
// stops forwarding instead of leaving silent inert rules behind.
func (m *nftablesManager) removePortForwardFamilyRules(ipVersion string) error {
	rules, err := m.PortForwards()
	if err != nil {
		return err
	}
	for _, rule := range rules {
		if !strings.EqualFold(rule.IPVersion, ipVersion) {
			continue
		}
		if err := m.deletePortForwardByHandle(rule); err != nil {
			return fmt.Errorf("delete %s port forward %s -> %s:%s: %w",
				rule.IPVersion, rule.ListenPort, rule.TargetIP, rule.TargetPort, err)
		}
	}
	return nil
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
