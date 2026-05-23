//go:build linux

package firewall

import (
	"net"
	"strings"
)

func detectExternalAccessPorts(clientIP string) ([]ExternalAccessPort, error) {
	ports := baselineExternalPorts()
	if !commandExists("ss") {
		return ports, nil
	}

	extra := make([]ExternalAccessPort, 0)
	extra = append(extra, parseSSEstablished("tcp", "ss", "-H", "-tn", "state", "established")...)
	extra = append(extra, parseSSEstablished("udp", "ss", "-H", "-un", "state", "established")...)

	if clientIP != "" {
		if ip := net.ParseIP(clientIP); ip != nil {
			for i := range extra {
				if extra[i].RemoteIP == clientIP {
					extra[i].Required = true
					extra[i].Label = "current_session"
				}
			}
		}
	}

	merged := mergeExternalPorts(ports, extra)
	return markClientSessionPort(merged, clientIP, configuredListenPort()), nil
}

func parseSSEstablished(proto string, cmd string, args ...string) []ExternalAccessPort {
	out, err := runCommand(cmd, args...)
	if err != nil {
		return nil
	}

	var ports []ExternalAccessPort
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}
		local := fields[len(fields)-2]
		peer := fields[len(fields)-1]
		_, localPort, ok := parseHostPort(local)
		if !ok || localPort == "" {
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
		ports = append(ports, ExternalAccessPort{
			Port:     localPort,
			Protocol: proto,
			RemoteIP: peerHost,
			Label:    "active_external",
		})
	}
	return ports
}
