package handlers

import (
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/utils"
)

// authenticateMonitorStream resolves user ID and role from ticket, Bearer JWT, or cookie.
func authenticateMonitorStream(c *gin.Context, jwtSecret string) (userID uint, role string, ok bool) {
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
		return claims.UserID, claims.Role, true
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
