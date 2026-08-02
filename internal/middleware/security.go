package middleware

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"
)

// SecurityMiddleware adds standard security headers to the response
func SecurityMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		connectSources := "'self'"
		if host := c.Request.Host; host != "" && !strings.ContainsAny(host, " \t\r\n;\"'") {
			connectSources += fmt.Sprintf(" ws://%s wss://%s", host, host)
		}
		c.Header("Content-Security-Policy", fmt.Sprintf("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self' https://npm.elemecdn.com https://cdn.jsdelivr.net data:; img-src 'self' data: blob:; media-src 'self' data: blob:; worker-src 'self' blob:; child-src 'self' blob:; connect-src %s; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self';", connectSources))

		// HTTP Strict Transport Security (HSTS) - 1 year
		c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

		// Prevent Clickjacking
		c.Header("X-Frame-Options", "DENY")

		// Prevent MIME type sniffing
		c.Header("X-Content-Type-Options", "nosniff")

		// XSS Protection
		c.Header("X-XSS-Protection", "1; mode=block")

		// Referrer Policy
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		c.Next()
	}
}
