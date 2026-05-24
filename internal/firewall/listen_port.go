package firewall

import (
	"os"
	"strconv"
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

func baselineAllowPorts() []string {
	ports := map[string]struct{}{"22": {}}
	ports[strconv.Itoa(configuredListenPort())] = struct{}{}
	out := make([]string, 0, len(ports))
	for p := range ports {
		out = append(out, p)
	}
	return out
}
