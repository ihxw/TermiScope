package middleware

import (
	"github.com/gin-gonic/gin"
)

// CORS middleware for handling Cross-Origin Resource Sharing
// Uses a whitelist of allowed origins for security
func CORS(allowedOrigins []string) gin.HandlerFunc {
	// Pre-compute whether wildcard is configured
	hasWildcard := false
	for _, o := range allowedOrigins {
		if o == "*" {
			hasWildcard = true
			break
		}
	}

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		// If no origin header, it's a same-origin request (automatically allowed)
		if origin == "" {
			c.Next()
			return
		}

		// Check if origin matches the request host (same-origin)
		host := c.Request.Header.Get("Host")
		if host != "" {
			requestOrigin := "http://" + host
			if origin == requestOrigin || origin == "https://"+host {
				c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
				c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
				c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
				c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")

				if c.Request.Method == "OPTIONS" {
					c.AbortWithStatus(204)
					return
				}
				c.Next()
				return
			}
		}

		// Check if origin is in the allowed list
		allowed := false
		for _, allowedOrigin := range allowedOrigins {
			if allowedOrigin == "*" || origin == allowedOrigin {
				allowed = true
				break
			}
		}

		if allowed {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			// Security: Do NOT send Allow-Credentials with wildcard origin
			if !hasWildcard {
				c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
			}
			c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
			c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		}

		if c.Request.Method == "OPTIONS" {
			if allowed {
				c.AbortWithStatus(204)
			} else {
				c.AbortWithStatus(403)
			}
			return
		}

		// Security: Block non-whitelisted origins for state-changing requests
		if !allowed && c.Request.Method != "GET" && c.Request.Method != "HEAD" {
			c.JSON(403, gin.H{
				"success": false,
				"error":   "origin not allowed",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}
