package utils

import (
	"debug/buildinfo"
	"regexp"
	"strings"
)

var agentVersionLdflagPattern = regexp.MustCompile(`(?:^|\s)-X=?\s*(?:main\.Version|github\.com/ihxw/termiscope/cmd/agent\.Version)=([^\s'"]+)`)

// AgentBinaryVersion extracts the Version value injected into a Go agent binary.
func AgentBinaryVersion(filePath string) (string, bool) {
	info, err := buildinfo.ReadFile(filePath)
	if err != nil {
		return "", false
	}

	for _, setting := range info.Settings {
		if setting.Key != "-ldflags" {
			continue
		}
		return ParseAgentVersionLdflags(setting.Value)
	}

	return "", false
}

func ParseAgentVersionLdflags(ldflags string) (string, bool) {
	matches := agentVersionLdflagPattern.FindStringSubmatch(ldflags)
	if len(matches) != 2 {
		return "", false
	}

	version := strings.TrimSpace(matches[1])
	version = strings.Trim(version, `"'`)
	if version == "" {
		return "", false
	}

	return version, true
}
