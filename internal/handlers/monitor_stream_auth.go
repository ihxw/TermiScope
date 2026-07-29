package handlers

import (
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// authenticateMonitorStream resolves user ID and role from ticket, Bearer JWT, or cookie.
func authenticateMonitorStream(c *gin.Context, jwtSecret string, db *gorm.DB) (userID uint, role string, ok bool) {
	tokenStr := c.Query("token")
	if tokenStr != "" {
		if td, valid := utils.ValidateTicket(tokenStr); valid {
			return td.UserID, td.Role, true
		}
	}

	tryToken := func(token string) (uint, string, bool) {
		if token == "" {
			return 0, "", false
		}
		if td, valid := utils.ValidateTicket(token); valid {
			return td.UserID, td.Role, true
		}
		claims, err := utils.ValidateToken(token, jwtSecret)
		if err != nil || claims.TokenType != "access" {
			return 0, "", false
		}
		if claims.ID != "" {
			if db == nil {
				return 0, "", false
			}
			var count int64
			if err := db.Model(&models.RevokedToken{}).Where("jti = ?", claims.ID).Count(&count).Error; err != nil || count > 0 {
				return 0, "", false
			}
		}
		var user models.User
		if err := db.First(&user, claims.UserID).Error; err != nil || !user.IsActive() || claims.TokenVersion != user.TokenVersion {
			return 0, "", false
		}
		return user.ID, user.Role, true
	}

	if authHeader := c.GetHeader("Authorization"); authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			if uid, r, valid := tryToken(parts[1]); valid {
				return uid, r, true
			}
		}
	}

	if cookie, err := c.Cookie("access_token"); err == nil {
		if uid, r, valid := tryToken(cookie); valid {
			return uid, r, true
		}
	}

	return 0, "", false
}
