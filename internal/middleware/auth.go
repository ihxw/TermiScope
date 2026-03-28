package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// AuthMiddleware validates JWT token and sets user context
func AuthMiddleware(jwtSecret string, db *gorm.DB) gin.HandlerFunc {
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

		// Security: Removed URL query parameter token support (c.Query("token"))
		// Tokens in URLs leak via logs, referer headers, and browser history.
		// WebSocket connections use ticket-based authentication instead.

		// If still no token, check for access_token cookie (for Media Streaming)
		if token == "" {
			if cookie, err := c.Cookie("access_token"); err == nil {
				token = cookie
			}
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
			// ... (existing logic)
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

		// Check if token is revoked
		if claims.ID != "" {
			var count int64
			db.Model(&models.RevokedToken{}).Where("jti = ?", claims.ID).Count(&count)
			if count > 0 {
				c.JSON(http.StatusUnauthorized, gin.H{
					"success": false,
					"error":   "token revoked",
				})
				c.Abort()
				return
			}
		}

		// Ensure it's an access token (unless it's a 2FA temp token which is used for intermediate steps, but here we usually expect access for protected routes)
		// Actually 2FA temp tokens shouldn't be used for general API access.
		// Ensure it's an access token
		if claims.TokenType != "access" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"error":   "invalid token type",
			})
			c.Abort()
			return
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
