//go:build windows

package firewall

func ruleToAddRequest(r Rule) AddRuleRequest {
	source := r.Source
	if source == "" {
		source = "any"
	}
	return AddRuleRequest{
		Action:    r.Action,
		Port:      r.Port,
		Protocol:  r.Protocol,
		Source:    source,
		Direction: r.Direction,
		Comment:   r.Comment,
	}
}

func portForwardRequestFromRule(rule PortForwardRule) AddPortForwardRequest {
	return AddPortForwardRequest{
		IPVersion:  rule.IPVersion,
		Protocol:   rule.Protocol,
		ListenPort: rule.ListenPort,
		ListenAddr: rule.ListenAddr,
		TargetIP:   rule.TargetIP,
		TargetPort: rule.TargetPort,
		Source:     rule.Source,
		Comment:    rule.Comment,
	}
}
