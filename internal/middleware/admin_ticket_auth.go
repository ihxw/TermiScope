package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// AdminOrTicketMiddleware allows admin JWT/cookie auth or a one-time ticket (query ?token=).
// Used for backup download via window.location where Authorization headers are not sent.
func AdminOrTicketMiddleware(jwtSecret string, db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		if authorizeAdmin(c, jwtSecret, db) {
			c.Next()
			return
		}
		c.JSON(http.StatusUnauthorized, gin.H{
			"success": false,
			"error":   "admin authorization required",
		})
		c.Abort()
	}
}

func authorizeAdmin(c *gin.Context, jwtSecret string, db *gorm.DB) bool {
	var token string

	if authHeader := c.GetHeader("Authorization"); authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			token = parts[1]
		}
	}
	if token == "" {
		if cookie, err := c.Cookie("access_token"); err == nil {
			token = cookie
		}
	}
	if token == "" {
		token = c.Query("token")
	}

	if token == "" {
		return false
	}

	if ticket, ok := utils.ValidateTicket(token); ok {
		if ticket.Role != "admin" {
			return false
		}
		c.Set("user_id", ticket.UserID)
		c.Set("username", ticket.Username)
		c.Set("role", ticket.Role)
		return true
	}

	claims, err := utils.ValidateToken(token, jwtSecret)
	if err != nil || claims.TokenType != "access" || claims.Role != "admin" {
		return false
	}

	if claims.ID != "" {
		var count int64
		db.Model(&models.RevokedToken{}).Where("jti = ?", claims.ID).Count(&count)
		if count > 0 {
			return false
		}
	}

	c.Set("user_id", claims.UserID)
	c.Set("username", claims.Username)
	c.Set("role", claims.Role)
	return true
}
