package firewall

import (
	"os"
	"strconv"
	"strings"
	"sync"
)

var (
	listenPortMu sync.RWMutex
	listenPort   = 8080
)

// SetListenPort records the TermiScope HTTP listen port for safe baseline firewall rules.
func SetListenPort(port int) {
	if port < 1 || port > 65535 {
		return
	}
	listenPortMu.Lock()
	listenPort = port
	listenPortMu.Unlock()
}

func configuredListenPort() int {
	listenPortMu.RLock()
	defer listenPortMu.RUnlock()
	if p := os.Getenv("TERMISCOPE_PORT"); p != "" {
		if n, err := strconv.Atoi(p); err == nil && n > 0 && n <= 65535 {
			return n
		}
	}
	return listenPort
}

// detectSSHPort reads the SSH server configuration and returns the configured port.
// Falls back to 22 if the config cannot be read or parsed.
func detectSSHPort() string {
	for _, path := range []string{"/etc/ssh/sshd_config", "/etc/ssh/ssh_config"} {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			fields := strings.Fields(line)
			if len(fields) >= 2 && strings.EqualFold(fields[0], "port") {
				port := fields[1]
				if _, err := strconv.Atoi(port); err == nil {
					return port
				}
			}
		}
	}
	return "22"
}

func baselineAllowPorts() []string {
	ssh := detectSSHPort()
	return []string{ssh}
}

func webUIPort() string {
	return strconv.Itoa(configuredListenPort())
}
