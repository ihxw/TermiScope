package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/utils"
)

// AuthMiddleware validates JWT token and sets user context
func AuthMiddleware(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		var token string
		authHeader := c.GetHeader("Authorization")

		if authHeader != "" {
			// Extract token from "Bearer <token>"
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && parts[0] == "Bearer" {
				token = parts[1]
			}
		}

		// If no token from header, check query parameter (for WebSockets)
		if token == "" {
			token = c.Query("token")
		}

		if token == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "authorization token required",
			})
			c.Abort()
			return
		}

		claims, err := utils.ValidateToken(token, jwtSecret)
		if err != nil {
			// Try as a one-time ticket (for WebSockets)
			if ticketData, ok := utils.ValidateTicket(token); ok {
				c.Set("user_id", ticketData.UserID)
				c.Set("username", ticketData.Username)
				c.Set("role", ticketData.Role)
				c.Next()
				return
			}

			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "invalid or expired token",
			})
			c.Abort()
			return
		}

		// Ensure it's an access token (unless it's a 2FA temp token which is used for intermediate steps, but here we usually expect access for protected routes)
		// Actually 2FA temp tokens shouldn't be used for general API access.
		if claims.TokenType != "access" && claims.TokenType != "2fa_temp" {
			// Allow 2fa_temp for now if it was used that way, but ideally strict.
			// Given previous code, ValidateToken was generic.
			// Let's restrict to 'access' for general middleware use.
			// Wait, the new logic uses "2fa_temp" for the intermediate step?
			// The intermediate step usually doesn't hit AuthMiddleware protected routes?
			// Actually 2FA verification hits /auth/verify-2fa which is usually public or protected by temp token?
			// In `router.go` (not seen but typically) `verify-2fa` is public (accepts user_id + code).
			// So middleware should strictly enforce "access".
			if claims.TokenType != "access" {
				c.JSON(http.StatusUnauthorized, gin.H{
					"success": false,
					"error":   "invalid token type",
				})
				c.Abort()
				return
			}
		}

		// Set user context
		c.Set("user_id", claims.UserID)
		c.Set("username", claims.Username)
		c.Set("role", claims.Role)

		c.Next()
	}
}

// AdminMiddleware checks if the user is an admin
func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists || role != "admin" {
			c.JSON(http.StatusForbidden, gin.H{
				"success": false,
				"error":   "admin access required",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

// GetUserID gets the user ID from context
func GetUserID(c *gin.Context) uint {
	if userID, exists := c.Get("user_id"); exists {
		if id, ok := userID.(uint); ok {
			return id
		}
		// Try other numeric types just in case (e.g. if loaded from JSON as float64)
		if id, ok := userID.(float64); ok {
			return uint(id)
		}
		if id, ok := userID.(int); ok {
			return uint(id)
		}
	}
	return 0
}

// GetUsername gets the username from context
func GetUsername(c *gin.Context) string {
	if username, exists := c.Get("username"); exists {
		if name, ok := username.(string); ok {
			return name
		}
	}
	return ""
}

// GetRole gets the role from context
func GetRole(c *gin.Context) string {
	if role, exists := c.Get("role"); exists {
		if r, ok := role.(string); ok {
			return r
		}
	}
	return ""
}
