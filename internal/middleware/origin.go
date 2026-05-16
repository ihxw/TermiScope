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

	if debugMode && isLocalOrPrivateOrigin(origin) {
		return true
	}

	for _, allowed := range allowedOrigins {
		if allowed == "*" || origin == allowed {
			return true
		}
	}

	return false
}

func isLocalOrPrivateOrigin(origin string) bool {
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
	if ip == nil {
		return false
	}

	return ip.IsLoopback() || ip.IsPrivate()
}
