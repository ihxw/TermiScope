package middleware

import (
	"log"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var sensitiveLogKeys = map[string]struct{}{
	"access_token":  {},
	"authorization": {},
	"password":      {},
	"refresh_token": {},
	"secret":        {},
	"ticket":        {},
	"token":         {},
}

// Logger middleware for logging HTTP requests
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		raw := sanitizeRawQuery(c.Request.URL.RawQuery)

		c.Next()

		latency := time.Since(start)
		method := c.Request.Method
		statusCode := c.Writer.Status()

		// Mask IP (e.g., 192.168.1.5 -> 192.168.1.*** or just ***)
		// For privacy, let's just log the first segment or complete mask if configured.
		// User requested removing sensitive info like IP.
		// Let's use a simple hash or just "REDACTED"
		maskedIP := "REDACTED"

		if raw != "" {
			path = path + "?" + raw
		}

		log.Printf("[%s] %d | %13v | %15s | %-7s %s",
			time.Now().Format("2006/01/02 15:04:05"),
			statusCode,
			latency,
			maskedIP,
			method,
			path,
		)
	}
}

func sanitizeRawQuery(raw string) string {
	if raw == "" {
		return ""
	}

	values, err := url.ParseQuery(raw)
	if err != nil {
		return "[invalid-query]"
	}
	for key := range values {
		if isSensitiveLogKey(key) {
			values[key] = []string{"REDACTED"}
		}
	}
	return values.Encode()
}

func isSensitiveLogKey(key string) bool {
	key = strings.ToLower(strings.TrimSpace(key))
	if _, ok := sensitiveLogKeys[key]; ok {
		return true
	}
	return strings.Contains(key, "token") ||
		strings.Contains(key, "secret") ||
		strings.Contains(key, "password")
}
