//go:build windows

package firewall

import (
	"fmt"
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
		return text, fmt.Errorf("%s", text)
	}
	return text, nil
}

func runCommandPrivileged(name string, args ...string) (string, error) {
	return runCommand(name, args...)
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
