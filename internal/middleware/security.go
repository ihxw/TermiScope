package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityMiddleware adds standard security headers to the response
func SecurityMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Content Security Policy
		// Allow scripts from self and inline for Vue/Vite
		c.Header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; font-src 'self' https://npm.elemecdn.com https://cdn.jsdelivr.net data:; img-src 'self' data:; connect-src 'self' ws: wss:;")

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
