//go:build windows

package firewall

import (
	"net"
	"strings"
)

func detectExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	ports := baselineExternalPorts()
	if !commandExists("netstat") {
		return markClientSessionPort(ports, clientIP, configuredListenPort()), nil
	}

	out, err := runCommand("netstat", "-n")
	if err != nil {
		return markClientSessionPort(ports, clientIP, configuredListenPort()), nil
	}

	extra := make([]ExternalAccessPort, 0)
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(strings.ToUpper(line), "TCP") && !strings.HasPrefix(strings.ToUpper(line), "UDP") {
			continue
		}
		if !strings.Contains(strings.ToUpper(line), "ESTABLISHED") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}
		proto := strings.ToLower(fields[0])
		local := fields[1]
		peer := fields[2]
		_, localPort, ok := parseHostPort(local)
		if !ok {
			continue
		}
		peerHost, _, ok := parseHostPort(peer)
		if !ok {
			continue
		}
		ip := net.ParseIP(peerHost)
		if !isPublicIP(ip) {
			continue
		}
		extra = append(extra, ExternalAccessPort{
			Port:     localPort,
			Protocol: proto,
			RemoteIP: peerHost,
			Label:    "active_external",
		})
	}
	merged := mergeExternalPorts(ports, extra)
	return markClientSessionPort(merged, clientIP, configuredListenPort()), nil
}
