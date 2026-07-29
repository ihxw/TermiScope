//go:build linux

package firewall

import (
	"os"
	"sort"
	"strings"
)

// libvirtBridgeNames returns active libvirt bridge interfaces (libvirt usually uses virbr*).
func libvirtBridgeNames() []string {
	entries, err := os.ReadDir("/sys/class/net")
	if err != nil {
		return nil
	}
	return libvirtBridgeNamesFromEntries(entries)
}

func libvirtBridgeNamesFromEntries(entries []os.DirEntry) []string {
	bridges := make([]string, 0, len(entries))
	for _, entry := range entries {
		name := strings.TrimSpace(entry.Name())
		if !strings.HasPrefix(name, "virbr") {
			continue
		}
		bridges = append(bridges, name)
	}
	sort.Strings(bridges)
	return bridges
}

func libvirtNetworkingActive() bool {
	return len(libvirtBridgeNames()) > 0
}
