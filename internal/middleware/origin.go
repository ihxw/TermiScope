package middleware

import (
	"net"
	"net/url"
	"strings"
)

// IsOriginAllowed reports whether the browser Origin may access this server.
func IsOriginAllowed(origin, host string, allowedOrigins []string, debugMode bool) bool {
	if origin == "" {
		return true
	}

	if host != "" {
		if origin == "http://"+host || origin == "https://"+host {
			return true
		}
	}

	// Debug: only loopback origins are auto-allowed (not entire RFC1918 — use allowed_origins for LAN dev).
	if debugMode && isLoopbackOrigin(origin) {
		return true
	}

	for _, allowed := range allowedOrigins {
		if allowed == "*" || origin == allowed {
			return true
		}
	}

	return false
}

func isLoopbackOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return false
	}

	host := u.Hostname()
	if host == "localhost" || host == "127.0.0.1" || host == "::1" {
		return true
	}

	if strings.HasSuffix(host, ".localhost") {
		return true
	}

	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}
