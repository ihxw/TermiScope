//go:build linux

package firewall

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func runCommand(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if text == "" {
			return "", fmt.Errorf("%s failed: %w", name, err)
		}
		return text, fmt.Errorf("%s: %s", name, text)
	}
	return text, nil
}

func runCommandPrivileged(name string, args ...string) (string, error) {
	if os.Geteuid() == 0 {
		return runCommand(name, args...)
	}
	if _, err := exec.LookPath("sudo"); err != nil {
		return runCommand(name, args...)
	}
	sudoArgs := append([]string{"-n", name}, args...)
	out, err := exec.Command("sudo", sudoArgs...).CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if text == "" {
			return "", fmt.Errorf("sudo %s failed: %w", name, err)
		}
		return text, fmt.Errorf("sudo %s: %s", name, text)
	}
	return text, nil
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// nftCommentValue returns an nft comment token for exec.Command argv.
// Non-ASCII, spaces, and most user text must be double-quoted for the nft parser.
func nftCommentValue(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return s
	}
	if isBareNFTComment(s) {
		return s
	}
	escaped := strings.ReplaceAll(s, `\`, `\\`)
	escaped = strings.ReplaceAll(escaped, `"`, `\"`)
	return `"` + escaped + `"`
}

func isBareNFTComment(s string) bool {
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		case r == '-', r == '_', r == '.':
		default:
			return false
		}
	}
	return len(s) > 0
}
