//go:build linux

package firewall

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

type exportedFirewall struct {
	Backend string
	Enabled bool
	Rules   []Rule
}

func detectActiveFirewall() (string, bool) {
	if commandExists("ufw") {
		out, err := runCommand("ufw", "status")
		if err == nil && strings.Contains(strings.ToLower(out), "status: active") {
			return "ufw", true
		}
	}

	if commandExists("systemctl") {
		out, err := runCommand("systemctl", "is-active", "firewalld")
		if err == nil && strings.TrimSpace(out) == "active" {
			return "firewalld", true
		}
	}

	if commandExists("iptables") {
		out, err := runCommand("iptables", "-L", "INPUT", "-n")
		if err == nil {
			lines := strings.Split(out, "\n")
			if len(lines) > 2 {
				return "iptables", true
			}
		}
	}

	if commandExists("ufw") {
		return "ufw", false
	}
	if commandExists("firewall-cmd") {
		return "firewalld", false
	}
	if commandExists("iptables") {
		return "iptables", false
	}

	return "", false
}

func exportExistingFirewall() (*exportedFirewall, error) {
	backend, enabled := detectActiveFirewall()
	if backend == "" {
		return &exportedFirewall{Backend: "", Enabled: false, Rules: nil}, nil
	}

	var rules []Rule
	var err error

	switch backend {
	case "ufw":
		rules, err = exportUFWRules()
	case "firewalld":
		rules, err = exportFirewalldRules()
	case "iptables":
		rules, err = exportIPTablesRules()
	default:
		return nil, fmt.Errorf("unsupported firewall backend: %s", backend)
	}
	if err != nil {
		return nil, fmt.Errorf("export %s rules: %w", backend, err)
	}

	return &exportedFirewall{
		Backend: backend,
		Enabled: enabled,
		Rules:   rules,
	}, nil
}

var ufwRuleLine = regexp.MustCompile(`^\[\s*(\d+)\]\s+(.+?)\s+(ALLOW|DENY|REJECT)\s+(IN|OUT|IN/OUT)\s+(.+)$`)

func exportUFWRules() ([]Rule, error) {
	out, err := runCommand("ufw", "status", "numbered")
	if err != nil {
		return nil, err
	}

	var rules []Rule
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "Status:") || strings.HasPrefix(line, "To ") || strings.HasPrefix(line, "--") {
			continue
		}

		matches := ufwRuleLine.FindStringSubmatch(line)
		if len(matches) != 6 {
			continue
		}

		num, _ := strconv.Atoi(matches[1])
		destPart := strings.TrimSpace(matches[2])
		action := strings.ToLower(matches[3])
		direction := strings.ToLower(matches[4])
		source := strings.TrimSpace(matches[5])

		if direction != "in" && direction != "in/out" {
			continue
		}

		rule := Rule{
			Number:      num,
			Action:      action,
			Direction:   "in",
			Source:      source,
			Destination: destPart,
			Raw:         line,
		}

		if idx := strings.Index(destPart, "#"); idx >= 0 {
			rule.Comment = strings.TrimSpace(destPart[idx+1:])
			destPart = strings.TrimSpace(destPart[:idx])
		}

		if slash := strings.Index(destPart, "/"); slash >= 0 {
			rule.Port = destPart[:slash]
			rule.Protocol = destPart[slash+1:]
		} else if destPart != "Anywhere" && destPart != "Anywhere (v6)" {
			rule.Port = destPart
		}

		if source == "Anywhere" || source == "Anywhere (v6)" {
			rule.Source = "any"
		}

		rules = append(rules, rule)
	}

	return rules, nil
}

func exportIPTablesRules() ([]Rule, error) {
	out, err := runCommand("iptables-save")
	if err != nil {
		out, err = runCommand("iptables", "-S", "INPUT")
		if err != nil {
			return nil, err
		}
	}

	var rules []Rule
	num := 0
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "-A INPUT") {
			continue
		}

		rule := parseIPTablesLine(line)
		if rule == nil {
			continue
		}
		num++
		rule.Number = num
		rule.Raw = line
		rules = append(rules, *rule)
	}

	return rules, nil
}

func parseIPTablesLine(line string) *Rule {
	fields := strings.Fields(line)
	if len(fields) < 3 {
		return nil
	}

	rule := &Rule{Direction: "in", Action: "allow", Source: "any"}

	for i := 0; i < len(fields); i++ {
		switch fields[i] {
		case "-p":
			if i+1 < len(fields) {
				rule.Protocol = strings.ToLower(fields[i+1])
				i++
			}
		case "--dport":
			if i+1 < len(fields) {
				rule.Port = fields[i+1]
				i++
			}
		case "-s", "--source":
			if i+1 < len(fields) {
				rule.Source = fields[i+1]
				i++
			}
		case "-j":
			if i+1 < len(fields) {
				switch strings.ToUpper(fields[i+1]) {
				case "ACCEPT":
					rule.Action = "allow"
				case "DROP":
					rule.Action = "deny"
				case "REJECT":
					rule.Action = "reject"
				default:
					return nil
				}
				i++
			}
		}
	}

	if rule.Port == "" && rule.Protocol == "" && rule.Source == "any" {
		return nil
	}
	return rule
}

func exportFirewalldRules() ([]Rule, error) {
	if !commandExists("firewall-cmd") {
		return nil, fmt.Errorf("firewall-cmd not found")
	}

	var rules []Rule
	num := 0

	out, err := runCommand("firewall-cmd", "--permanent", "--list-ports")
	if err == nil {
		for _, token := range strings.Fields(out) {
			parts := strings.Split(token, "/")
			if len(parts) != 2 {
				continue
			}
			num++
			rules = append(rules, Rule{
				Number:    num,
				Action:    "allow",
				Direction: "in",
				Port:      parts[0],
				Protocol:  parts[1],
				Source:    "any",
				Raw:       "firewalld port " + token,
			})
		}
	}

	servicesOut, err := runCommand("firewall-cmd", "--permanent", "--list-services")
	if err == nil {
		for _, svc := range strings.Fields(servicesOut) {
			num++
			rules = append(rules, Rule{
				Number:    num,
				Action:    "allow",
				Direction: "in",
				Comment:   "service:" + svc,
				Source:    "any",
				Raw:       "firewalld service " + svc,
			})
		}
	}

	richOut, err := runCommand("firewall-cmd", "--permanent", "--list-rich-rules")
	if err == nil {
		for _, line := range strings.Split(richOut, "\n") {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			if r := parseFirewalldRichRule(line); r != nil {
				num++
				r.Number = num
				r.Raw = line
				rules = append(rules, *r)
			}
		}
	}

	return rules, nil
}

var richPortRe = regexp.MustCompile(`port="(\d+(?:-\d+)?)"`)
var richProtoRe = regexp.MustCompile(`protocol="(\w+)"`)
var richSourceRe = regexp.MustCompile(`source address="([^"]+)"`)
var richActionRe = regexp.MustCompile(`\b(accept|drop|reject)\b`)

func parseFirewalldRichRule(line string) *Rule {
	actionMatch := richActionRe.FindStringSubmatch(strings.ToLower(line))
	if len(actionMatch) != 2 {
		return nil
	}

	rule := &Rule{Direction: "in", Source: "any"}
	switch actionMatch[1] {
	case "accept":
		rule.Action = "allow"
	case "drop":
		rule.Action = "deny"
	case "reject":
		rule.Action = "reject"
	}

	if m := richPortRe.FindStringSubmatch(line); len(m) == 2 {
		rule.Port = m[1]
	}
	if m := richProtoRe.FindStringSubmatch(line); len(m) == 2 {
		rule.Protocol = strings.ToLower(m[1])
	}
	if m := richSourceRe.FindStringSubmatch(line); len(m) == 2 {
		rule.Source = m[1]
	}

	return rule
}

func disablePreviousFirewall(backend string) error {
	switch backend {
	case "ufw":
		_, err := runCommandPrivileged("ufw", "disable")
		return err
	case "firewalld":
		if commandExists("systemctl") {
			_, _ = runCommandPrivileged("systemctl", "stop", "firewalld")
			_, err := runCommandPrivileged("systemctl", "disable", "firewalld")
			return err
		}
		return nil
	case "iptables":
		// Never flush iptables here — it breaks Docker and can remove SSH allow rules.
		if commandExists("systemctl") {
			_, _ = runCommandPrivileged("systemctl", "stop", "iptables")
			_, _ = runCommandPrivileged("systemctl", "disable", "iptables")
		}
		return nil
	default:
		return nil
	}
}

func ruleToAddRequest(r Rule) AddRuleRequest {
	source := r.Source
	if source == "" {
		source = "any"
	}
	return AddRuleRequest{
		Action:   r.Action,
		Port:     r.Port,
		Protocol: r.Protocol,
		Source:   source,
		Comment:  r.Comment,
	}
}
