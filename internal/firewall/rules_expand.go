package firewall

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

func normalizeDirection(dir string) string {
	dir = strings.ToLower(strings.TrimSpace(dir))
	switch dir {
	case "", "in", "input":
		return "in"
	case "out", "output":
		return "out"
	default:
		return dir
	}
}

func normalizeProtocols(protocol string) []string {
	p := strings.ToLower(strings.TrimSpace(protocol))
	switch p {
	case "", "any":
		return nil
	case "both", "tcp+udp", "tcpudp", "tcp/udp":
		return []string{"tcp", "udp"}
	case "tcp", "udp":
		return []string{p}
	default:
		return []string{p}
	}
}

func sourceForRule(source string) string {
	source = strings.TrimSpace(source)
	if source == "" || source == "any" || source == "0.0.0.0/0" || source == "::/0" {
		return "any"
	}
	return source
}

func parsePortField(port string) ([]string, error) {
	port = strings.TrimSpace(port)
	if port == "" {
		return nil, nil
	}
	raw := strings.Split(port, ",")
	out := make([]string, 0, len(raw))
	for _, part := range raw {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if !portPattern.MatchString(part) {
			return nil, fmt.Errorf("invalid port format")
		}
		parts := strings.Split(part, ":")
		for _, p := range parts {
			n, err := strconv.Atoi(p)
			if err != nil || n < 1 || n > 65535 {
				return nil, fmt.Errorf("port must be between 1 and 65535")
			}
		}
		out = append(out, part)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("invalid port format")
	}
	return out, nil
}

// ExpandAddRuleRequests splits tcp+udp and comma-separated ports into nft/netsh rule payloads.
func ExpandAddRuleRequests(req AddRuleRequest) ([]AddRuleRequest, error) {
	if err := ValidateAddRule(req); err != nil {
		return nil, err
	}

	ports, err := parsePortField(req.Port)
	if err != nil {
		return nil, err
	}

	protocols := normalizeProtocols(req.Protocol)
	if len(protocols) == 0 && len(ports) > 0 {
		protocols = []string{"tcp"}
	}
	if len(protocols) == 0 {
		protocols = []string{""}
	}

	req.Direction = normalizeDirection(req.Direction)
	req.Source = sourceForRule(req.Source)

	var out []AddRuleRequest
	for _, proto := range protocols {
		r := req
		r.Protocol = proto
		if len(ports) == 0 {
			out = append(out, r)
			continue
		}
		if len(ports) == 1 {
			r.Port = ports[0]
			out = append(out, r)
			continue
		}
		r.Port = strings.Join(ports, ",")
		out = append(out, r)
	}
	return out, nil
}

func appendNFTPortMatch(args []string, portField string) []string {
	ports, err := parsePortField(portField)
	if err != nil || len(ports) == 0 {
		return args
	}
	if len(ports) == 1 {
		return append(args, "dport", ports[0])
	}
	return append(args, "dport", "{"+strings.Join(ports, ", ")+"}")
}

// appendNFTProtocolPortMatch builds nft match tokens. Bare "tcp"/"udp" must be followed by
// dport; protocol-only rules use "meta l4proto" (e.g. outbound allow all TCP).
func appendNFTProtocolPortMatch(args []string, protocol, portField string) []string {
	protocol = strings.ToLower(strings.TrimSpace(protocol))
	portField = strings.TrimSpace(portField)
	ports, err := parsePortField(portField)
	if err != nil {
		ports = nil
	}

	if protocol != "" && len(ports) > 0 {
		args = append(args, protocol)
		return appendNFTPortMatch(args, portField)
	}
	if protocol != "" {
		return append(args, "meta", "l4proto", protocol)
	}
	if len(ports) > 0 {
		args = append(args, "tcp")
		return appendNFTPortMatch(args, portField)
	}
	return args
}

func isPublicIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() {
		return false
	}
	return !ip.IsPrivate() && !ip.IsLoopback() && !ip.IsLinkLocalUnicast()
}

func parseHostPort(addr string) (host string, port string, ok bool) {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return "", "", false
	}
	if strings.HasPrefix(addr, "[") {
		host, rest, found := strings.Cut(strings.TrimPrefix(addr, "["), "]")
		if !found {
			return "", "", false
		}
		rest = strings.TrimPrefix(rest, ":")
		return host, rest, rest != ""
	}
	if strings.Count(addr, ":") > 1 {
		// IPv6 without brackets: last colon separates port
		if i := strings.LastIndex(addr, ":"); i > 0 {
			return addr[:i], addr[i+1:], true
		}
		return "", "", false
	}
	host, port, found := strings.Cut(addr, ":")
	return host, port, found
}
