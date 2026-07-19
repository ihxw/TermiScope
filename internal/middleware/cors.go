package middleware

import (
	"github.com/gin-gonic/gin"
)

// CORS middleware for handling Cross-Origin Resource Sharing
// Uses a whitelist of allowed origins for security
func CORS(allowedOrigins []string, debugMode bool) gin.HandlerFunc {
	hasWildcard := false
	for _, o := range allowedOrigins {
		if o == "*" {
			hasWildcard = true
			break
		}
	}

	return func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")

		if origin == "" {
			c.Next()
			return
		}

		host := c.Request.Host
		if host == "" {
			host = c.Request.Header.Get("Host")
		}
		allowed := IsOriginAllowed(origin, host, allowedOrigins, debugMode)

		if allowed {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			if !hasWildcard {
				c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
			}
			c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, X-Termiscope-Editor, Authorization, accept, origin, Cache-Control, X-Requested-With")
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
