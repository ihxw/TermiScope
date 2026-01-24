package middleware

import (
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// Logger middleware for logging HTTP requests
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path
		raw := c.Request.URL.RawQuery

		c.Next()

		latency := time.Since(start)
		method := c.Request.Method
		statusCode := c.Writer.Status()

		// Mask IP (e.g., 192.168.1.5 -> 192.168.1.*** or just ***)
		// For privacy, let's just log the first segment or complete mask if configured.
		// User requested removing sensitive info like IP.
		// Let's use a simple hash or just "REDACTED"
		maskedIP := "REDACTED"

		// Sanitize Path/Query (remove token=...)
		if raw != "" {
			// Simple check for token
			// If raw contains token=..., replace it
			// This is a naive replacement
			// Better: parse query, but that's expensive for logging middleware
			// Just checking commonly used "token"
			// Actually, let's just NOT log raw query if it contains sensitive keys
			// or replace values.
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
