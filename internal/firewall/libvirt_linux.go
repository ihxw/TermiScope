//go:build linux

package firewall

import "os"

// libvirtBridgeNames returns active libvirt bridge interfaces (default network uses virbr0).
func libvirtBridgeNames() []string {
	const defaultBridge = "virbr0"
	if _, err := os.Stat("/sys/class/net/" + defaultBridge); err == nil {
		return []string{defaultBridge}
	}
	return nil
}

func libvirtNetworkingActive() bool {
	return len(libvirtBridgeNames()) > 0
}
