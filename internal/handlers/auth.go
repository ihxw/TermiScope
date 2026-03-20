package handlers

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type AuthHandler struct {
	db     *gorm.DB
	config *config.Config
}

func NewAuthHandler(db *gorm.DB, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		db:     db,
		config: cfg,
	}
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	Remember bool   `json:"remember"`
}

type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required,min=6"`
}

type LoginResponse struct {
	Token        string       `json:"token"`
	RefreshToken string       `json:"refresh_token"`
	User         *models.User `json:"user"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *AuthHandler) generateTokens(user *models.User) (string, string, error) {
	log.Printf("DEBUG: Generating tokens with AccessExpiration config: %s", h.config.Security.AccessExpiration)
	accessExp, err := time.ParseDuration(h.config.Security.AccessExpiration)
	if err != nil {
		accessExp = 60 * time.Minute
	}

	refreshExp, err := time.ParseDuration(h.config.Security.RefreshExpiration)
	if err != nil {
		refreshExp = 168 * time.Hour // 7 days
	}

	accessToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "access", accessExp, h.config.Security.JWTSecret)
	if err != nil {
		return "", "", err
	}

	refreshToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "refresh", refreshExp, h.config.Security.JWTSecret)
	if err != nil {
		return "", "", err
	}

	return accessToken, refreshToken, nil
}

// Login handles user login
// @Summary User Login
// @Description Authenticates a user and returns access/refresh tokens.
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body LoginRequest true "Login Credentials"
// @Success 200 {object} LoginResponse
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Invalid credentials"
// @Router /auth/login [post]
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Record invalid request
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityLow,
			0, "", c.ClientIP(), c.Request.UserAgent(), "Invalid request", nil)
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Find user by username or email
	var user models.User
	result := h.db.Where("username = ? OR email = ?", req.Username, req.Username).First(&user)
	if result.Error != nil {
		// Mitigate username enumeration
		bcrypt.CompareHashAndPassword([]byte("$2a$10$X7...dummyhash..."), []byte(req.Password))
		
		// Record login failure (unknown user)
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityLow,
			0, req.Username, c.ClientIP(), c.Request.UserAgent(), "Unknown user", nil)
		
		// Check for brute force
		if models.CheckBruteForce(h.db, c.ClientIP(), 15*time.Minute, 10) {
			models.SecurityEventLog(h.db, models.BruteForceDetected, models.SeverityHigh,
				0, "", c.ClientIP(), c.Request.UserAgent(), "Brute force attack detected", nil)
		}
		
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	// Check if user is active
	if !user.IsActive() {
		models.SecurityEventLog(h.db, models.PermissionDenied, models.SeverityMedium,
			user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Inactive user attempted login", nil)
		utils.ErrorResponse(c, http.StatusForbidden, "account is disabled")
		return
	}

	// Verify password
	if !user.CheckPassword(req.Password) {
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityMedium,
			user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Incorrect password", nil)
		
		// Check for brute force
		if models.CheckBruteForce(h.db, c.ClientIP(), 15*time.Minute, 10) {
			models.SecurityEventLog(h.db, models.BruteForceDetected, models.SeverityHigh,
				user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Brute force attack detected", nil)
		}
		
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	// Check if 2FA is enabled
	if user.TwoFactorEnabled {
		// Generate a temporary token for 2FA verification (short lived, e.g. 5 mins)
		tempToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "2fa_temp", 5*time.Minute, h.config.Security.JWTSecret)
		if err != nil {
			models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityHigh,
				user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Failed to generate 2FA token", nil)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate token")
			return
		}

		// Record 2FA required
		models.SecurityEventLog(h.db, models.TwoFAEnabled, models.SeverityLow,
			user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "2FA verification required", nil)

		utils.SuccessResponse(c, http.StatusOK, gin.H{
			"requires_2fa": true,
			"temp_token":   tempToken,
			"user_id":      user.ID,
		})
		return
	}

	accessToken, refreshToken, err := h.generateTokens(&user)
	if err != nil {
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityHigh,
			user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Failed to generate tokens", nil)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate tokens")
		return
	}

	// Update last login time
	now := time.Now()
	user.LastLoginAt = &now
	h.db.Save(&user)

	// Record successful login
	models.SecurityEventLog(h.db, models.LoginSuccess, models.SeverityLow,
		user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "Login successful", nil)

	// Auto-add origin if not already present (run in background)
	// Security Risk: Disable TOFU (Trust on First Use) for CORS to prevent phishing attacks adding malicious origins
	// go h.autoAddOrigin(c)

	// Record Login History
	// We need to parse the token to get JTI, but GenerateToken returns string.
	// To avoid re-parsing, we might need to refactor GenerateToken or just parse it here.
	// Actually, for simplicity and since we just generated it, we can parse it back or update GenerateToken to return JTI.
	// But `utils.GenerateToken` is used elsewhere. Let's just parse it back quickly or extract JTI if we change GenerateToken.
	// A better way: The previous step modified `GenerateToken` to put JTI in claims.
	// Let's parse it to get JTI.
	var jti string
	var refreshJti string

	claimsParsed, _ := utils.ValidateToken(accessToken, h.config.Security.JWTSecret)
	if claimsParsed != nil {
		jti = claimsParsed.ID
	}

	refreshClaimsParsed, _ := utils.ValidateToken(refreshToken, h.config.Security.JWTSecret)
	if refreshClaimsParsed != nil {
		refreshJti = refreshClaimsParsed.ID
	}

	var expiresAt *time.Time
	if claimsParsed != nil && claimsParsed.ExpiresAt != nil {
		t := claimsParsed.ExpiresAt.Time
		expiresAt = &t
	}

	loginHistory := models.LoginHistory{
		UserID:          user.ID,
		Username:        user.Username,
		IPAddress:       c.ClientIP(),
		UserAgent:       c.Request.UserAgent(),
		JTI:             jti,
		RefreshTokenJTI: refreshJti,
		LoginAt:         time.Now(),
		ExpiresAt:       expiresAt,
	}
	h.db.Create(&loginHistory)

	// Set access_token cookie for browser-based access (e.g. Swagger UI, Media Stream)
	// Path: "/" so it works for all routes
	// HttpOnly: true so JS cannot read it (XSS protection)
	// Secure: false (for now, ideally true if TLS enabled)
	// MaxAge: match access expiration
	accessDuration, _ := time.ParseDuration(h.config.Security.AccessExpiration)
	if accessDuration == 0 {
		accessDuration = 60 * time.Minute
	}
	c.SetCookie("access_token", accessToken, int(accessDuration.Seconds()), "/", "", false, true)

	utils.SuccessResponse(c, http.StatusOK, LoginResponse{
		Token:        accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	})
}

// RefreshToken handles token refresh
// @Summary Refresh Token
// @Description Refreshes the access token using a valid refresh token.
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body RefreshTokenRequest true "Refresh Token"
// @Success 200 {object} map[string]string "New Access Token"
// @Failure 400 {object} map[string]string "Invalid request"
// @Failure 401 {object} map[string]string "Invalid token"
// @Router /auth/refresh [post]
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Validate the refresh token and log detailed error information
	claims, err := utils.ValidateToken(req.RefreshToken, h.config.Security.JWTSecret)
	if err != nil {
		// Log detailed error for diagnostics
		utils.LogError("Refresh token validation failed: %v | IP: %s | Token prefix: %s...",
			err, c.ClientIP(),
			func() string {
				if len(req.RefreshToken) > 20 {
					return req.RefreshToken[:20]
				}
				return "(too short)"
			}())
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid refresh token")
		return
	}

	if claims.TokenType != "refresh" {
		utils.LogError("Invalid token type in refresh request: expected 'refresh', got '%s' | User ID: %d | IP: %s",
			claims.TokenType, claims.UserID, c.ClientIP())
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid token type")
		return
	}

	// Check if Refresh Token is revoked
	if claims.ID != "" {
		var count int64
		h.db.Model(&models.RevokedToken{}).Where("jti = ?", claims.ID).Count(&count)
		if count > 0 {
			utils.LogError("Revoked refresh token used: %s | User ID: %d", claims.ID, claims.UserID)
			utils.ErrorResponse(c, http.StatusUnauthorized, "token revoked")
			return
		}
	}

	// Check if user still exists and is active
	var user models.User
	if err := h.db.First(&user, claims.UserID).Error; err != nil {
		utils.LogError("User not found during token refresh: User ID: %d | Error: %v | IP: %s",
			claims.UserID, err, c.ClientIP())
		utils.ErrorResponse(c, http.StatusUnauthorized, "user invalid")
		return
	}
	if !user.IsActive() {
		utils.LogError("Inactive user attempted token refresh: User ID: %d | Username: %s | IP: %s",
			user.ID, user.Username, c.ClientIP())
		utils.ErrorResponse(c, http.StatusUnauthorized, "user invalid")
		return
	}

	// Generate new access token
	accessExp, err := time.ParseDuration(h.config.Security.AccessExpiration)
	if err != nil {
		utils.LogError("Failed to parse access expiration duration: %v, using default 60m", err)
		accessExp = 60 * time.Minute
	}

	accessToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "access", accessExp, h.config.Security.JWTSecret)
	if err != nil {
		utils.LogError("Failed to generate access token for user %d: %v", user.ID, err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	// Note: We are NOT rotating the Refresh token here (it stays valid until expiration or revocation).
	// If we wanted to rotate, we would declare the old one revoked and issue a new one.

	log.Printf("Token refreshed successfully for user %d (%s) | IP: %s | New expiration: %s",
		user.ID, user.Username, c.ClientIP(), time.Now().Add(accessExp).Format(time.RFC3339))

	// Update cookie
	c.SetCookie("access_token", accessToken, int(accessExp.Seconds()), "/", "", false, true)

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"token": accessToken,
	})
}

// Logout handles user logout
// @Summary Logout
// @Description Logs out the user (client-side action for JWT, clears cookie).
// @Tags Auth
// @Security BearerAuth
// @Success 200 {object} map[string]string "Success message"
// @Router /auth/logout [post]
func (h *AuthHandler) Logout(c *gin.Context) {
	// Extract token to revoke it
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {
		parts := strings.Split(authHeader, " ")
		if len(parts) == 2 && parts[0] == "Bearer" {
			tokenString := parts[1]
			claims, err := utils.ValidateToken(tokenString, h.config.Security.JWTSecret)
			if err == nil && claims.ID != "" {
				// Save to revoked tokens
				revoked := models.RevokedToken{
					JTI:       claims.ID,
					UserID:    claims.UserID,
					ExpiresAt: claims.ExpiresAt.Time,
				}
				h.db.Create(&revoked)

				// Also try to revoke the associated refresh token if we can find it in LoginHistory
				// Note: accessing DB here might be slight overhead but ensures cleanliness
				var history models.LoginHistory
				if err := h.db.Where("jti = ?", claims.ID).First(&history).Error; err == nil && history.RefreshTokenJTI != "" {
					revokedRefresh := models.RevokedToken{
						JTI:       history.RefreshTokenJTI,
						UserID:    claims.UserID,
						ExpiresAt: time.Now().Add(7 * 24 * time.Hour), // Assume 7 days
					}
					h.db.Create(&revokedRefresh)
				}
			}
		}
	}

	// Clear cookie
	c.SetCookie("access_token", "", -1, "/", "", false, true)

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "logged out successfully",
	})
}

// GetLoginHistory retrieves the login history for the current user
// @Summary Get login history
// @Description Get list of login sessions
// @Tags Auth
// @Security BearerAuth
// @Param page query int false "Page number"
// @Param page_size query int false "Page size"
// @Success 200 {object} map[string]interface{} "Login history"
// @Router /auth/login-history [get]
func (h *AuthHandler) GetLoginHistory(c *gin.Context) {
	userID := middleware.GetUserID(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "10"))

	// Check user role for admin access? Usually users see their own.
	// If admin wants to see others, that's a different endpoint usually.
	// Requirement: "Web login history... separate tab". Usually implies own history or admin view of self?
	// Given "force logout already logged in devices", it implies managing OWN sessions.

	var logs []models.LoginHistory
	var total int64

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.LoginHistory{}).Where("user_id = ?", userID)
	query.Count(&total)

	query.Order("login_at desc").Offset(offset).Limit(pageSize).Find(&logs)

	// Check status of each log (Active/Revoked/Expired)
	// This is a bit expensive if we check DB for each, but we can check RevokedToken table for JTI.
	// Or we can allow the frontend to check active/revoked if we return JTI status.
	// Let's do a left join or just iterate if page size is small.

	// Fetch revoked JTIs for these logs
	var jtis []string
	for _, log := range logs {
		if log.JTI != "" {
			jtis = append(jtis, log.JTI)
		}
	}

	revokedMap := make(map[string]bool)
	if len(jtis) > 0 {
		var revokedTokens []models.RevokedToken
		h.db.Where("jti IN ?", jtis).Find(&revokedTokens)
		for _, t := range revokedTokens {
			revokedMap[t.JTI] = true
		}
	}

	// Prepare response with detailed status
	var result []map[string]interface{}
	for _, l := range logs {
		status := "Active"
		if revokedMap[l.JTI] {
			status = "Revoked"
		} else if l.ExpiresAt != nil && l.ExpiresAt.Before(time.Now()) {
			status = "Expired"
		}

		// Check if it's CURRENT session
		currentJTI := ""
		// Extract JTI from current context token?
		// We can get token from header again
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) == 2 {
				// We don't want to parse fully again, but we could if needed.
				// Middleware could set JTI in context.
				// For now let's just leave "Current" logic to frontend or verify token here.
				// Since we need to match JTI.
				claims, _ := utils.ValidateToken(parts[1], h.config.Security.JWTSecret)
				if claims != nil {
					currentJTI = claims.ID
				}
			}
		}

		isCurrent := (l.JTI == currentJTI)

		result = append(result, map[string]interface{}{
			"id":         l.ID,
			"ip_address": l.IPAddress,
			"user_agent": l.UserAgent,
			"login_at":   l.LoginAt,
			"status":     status,
			"is_current": isCurrent,
			"jti":        l.JTI,
		})
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"data": result,
		"pagination": gin.H{
			"current":  page,
			"pageSize": pageSize,
			"total":    total,
		},
	})
}

// RevokeSession revokes a specific session (force logout)
// @Summary Revoke session
// @Description Force logout a session by JTI
// @Tags Auth
// @Security BearerAuth
// @Param request body struct{JTI string} true "JTI to revoke"
// @Success 200 {object} map[string]string "Success message"
// @Router /auth/sessions/revoke [post]
func (h *AuthHandler) RevokeSession(c *gin.Context) {
	var req struct {
		JTI string `json:"jti" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "Invalid request")
		return
	}

	userID := middleware.GetUserID(c)

	// Verify the JTI belongs to the user (security check)
	var log models.LoginHistory
	if err := h.db.Where("jti = ? AND user_id = ?", req.JTI, userID).First(&log).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "Session not found or access denied")
		return
	}

	// Add to revoked tokens
	// Expiry? We should set it to somewhat far future or match the token's original expiry.
	// Since we don't know exact token expiry here easily without parsing content (which we don't have stored fully),
	// we'll assume standard token duration (e.g., 24h) from LoginAt or just 24h from now to be safe.
	// Or better: set it to a reasonable max like 7 days.
	// The middleware checks existence in RevokedTokens.
	revoked := models.RevokedToken{
		JTI:       req.JTI,
		UserID:    userID,
		ExpiresAt: time.Now().Add(24 * time.Hour), // Default backup expiry for access token
	}
	h.db.Create(&revoked)

	// Revoke associated Refresh Token
	if log.RefreshTokenJTI != "" {
		revokedRefresh := models.RevokedToken{
			JTI:       log.RefreshTokenJTI,
			UserID:    userID,
			ExpiresAt: time.Now().Add(7 * 24 * time.Hour), // Refresh tokens live longer
		}
		h.db.Create(&revokedRefresh)
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "Session revoked successfully",
	})
}

// GetCurrentUser returns the current authenticated user
// @Summary Get Current User
// @Description Returns the profile of the currently logged-in user.
// @Tags Auth
// @Security BearerAuth
// @Produce json
// @Success 200 {object} models.User
// @Failure 404 {object} map[string]string "User not found"
// @Router /auth/me [get]
func (h *AuthHandler) GetCurrentUser(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, &user)
}

// GetWSTicket generates a one-time ticket for WebSocket connection
func (h *AuthHandler) GetWSTicket(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid user context")
		return
	}

	username := middleware.GetUsername(c)
	role := middleware.GetRole(c)

	ticket := utils.GenerateTicket(userID, username, role)

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"ticket": ticket,
	})
}

// GetTokenInfo returns information about the current user's tokens (diagnostic endpoint)
func (h *AuthHandler) GetTokenInfo(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID == 0 {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid user context")
		return
	}

	// Get token from header
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		utils.ErrorResponse(c, http.StatusUnauthorized, "no token provided")
		return
	}

	// Extract token
	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid authorization header")
		return
	}
	tokenString := parts[1]

	// Validate and get claims
	claims, err := utils.ValidateToken(tokenString, h.config.Security.JWTSecret)
	if err != nil {
		utils.ErrorResponse(c, http.StatusUnauthorized, fmt.Sprintf("token validation failed: %v", err))
		return
	}

	// Parse configured expirations
	accessExp, _ := time.ParseDuration(h.config.Security.AccessExpiration)
	refreshExp, _ := time.ParseDuration(h.config.Security.RefreshExpiration)

	// Calculate time until expiration
	var timeUntilExpiry string
	if claims.ExpiresAt != nil {
		remaining := time.Until(claims.ExpiresAt.Time)
		timeUntilExpiry = remaining.String()
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"user_id":                     userID,
		"token_type":                  claims.TokenType,
		"issued_at":                   claims.IssuedAt.Time.Format(time.RFC3339),
		"expires_at":                  claims.ExpiresAt.Time.Format(time.RFC3339),
		"time_until_expiry":           timeUntilExpiry,
		"access_expiration_cfg":       h.config.Security.AccessExpiration,
		"refresh_expiration_cfg":      h.config.Security.RefreshExpiration,
		"access_expiration_duration":  accessExp.String(),
		"refresh_expiration_duration": refreshExp.String(),
	})
}

type Verify2FALoginRequest struct {
	UserID uint   `json:"user_id" binding:"required"`
	Code   string `json:"code" binding:"required"`
	Token  string `json:"token" binding:"required"`
}

// Verify2FALogin verifies 2FA code and completes login
func (h *AuthHandler) Verify2FALogin(c *gin.Context) {
	var req Verify2FALoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Validate temp token
	claims, err := utils.ValidateToken(req.Token, h.config.Security.JWTSecret)
	if err != nil {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid or expired session token")
		return
	}

	// Check token type
	if claims.TokenType != "2fa_temp" {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid token type")
		return
	}

	// Check if token belongs to the user
	if claims.UserID != req.UserID {
		utils.ErrorResponse(c, http.StatusUnauthorized, "token does not match user")
		return
	}

	var user models.User
	if err := h.db.First(&user, req.UserID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	if !user.TwoFactorEnabled {
		utils.ErrorResponse(c, http.StatusBadRequest, "2FA is not enabled")
		return
	}

	// Decrypt secret
	secret, err := utils.Decrypt(user.TwoFactorSecret, h.config.Security.EncryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to decrypt secret")
		return
	}

	// Verify the code
	valid := totp.Validate(req.Code, secret)
	if !valid {
		// Check backup codes
		validBackup, newEncryptedCodes := h.verifyBackupCode(req.Code, user.BackupCodes)
		if !validBackup {
			utils.ErrorResponse(c, http.StatusUnauthorized, "invalid verification code")
			return
		}
		// Code was valid backup code, update user with remaining codes
		user.BackupCodes = newEncryptedCodes
	}

	accessToken, refreshToken, err := h.generateTokens(&user)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate tokens")
		return
	}

	// Update last login time
	now := time.Now()
	user.LastLoginAt = &now
	h.db.Save(&user)

	// Record Login History for 2FA login
	var jti string
	var refreshJti string
	var expiresAt *time.Time

	claimsParsed, _ := utils.ValidateToken(accessToken, h.config.Security.JWTSecret)
	if claimsParsed != nil {
		jti = claimsParsed.ID
		if claimsParsed.ExpiresAt != nil {
			t := claimsParsed.ExpiresAt.Time
			expiresAt = &t
		}
	}

	refreshClaimsParsed, _ := utils.ValidateToken(refreshToken, h.config.Security.JWTSecret)
	if refreshClaimsParsed != nil {
		refreshJti = refreshClaimsParsed.ID
	}

	loginHistory := models.LoginHistory{
		UserID:          user.ID,
		Username:        user.Username,
		IPAddress:       c.ClientIP(),
		UserAgent:       c.Request.UserAgent(),
		JTI:             jti,
		RefreshTokenJTI: refreshJti,
		LoginAt:         time.Now(),
		ExpiresAt:       expiresAt,
	}
	h.db.Create(&loginHistory)

	// Set cookie
	accessDuration, _ := time.ParseDuration(h.config.Security.AccessExpiration)
	if accessDuration == 0 {
		accessDuration = 60 * time.Minute
	}
	c.SetCookie("access_token", accessToken, int(accessDuration.Seconds()), "/", "", false, true)

	// Return response
	utils.SuccessResponse(c, http.StatusOK, LoginResponse{
		Token:        accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	})
}

func (h *AuthHandler) verifyBackupCode(code, encryptedCodes string) (bool, string) {
	if encryptedCodes == "" {
		return false, ""
	}

	decrypted, err := utils.Decrypt(encryptedCodes, h.config.Security.EncryptionKey)
	if err != nil {
		return false, ""
	}

	var hashedCodes []string
	if err := json.Unmarshal([]byte(decrypted), &hashedCodes); err != nil {
		return false, ""
	}

	for i, hash := range hashedCodes {
		if bcrypt.CompareHashAndPassword([]byte(hash), []byte(code)) == nil {
			// Code matches, consume it by removing from slice
			hashedCodes = append(hashedCodes[:i], hashedCodes[i+1:]...)

			// Re-encrypt remaining codes
			data, _ := json.Marshal(hashedCodes)
			newEncrypted, err := utils.Encrypt(string(data), h.config.Security.EncryptionKey)
			if err != nil {
				// Should not happen, but safe fallback
				return true, encryptedCodes
			}
			return true, newEncrypted
		}
	}

	return false, ""
}

// ChangePassword allows users to change their own password
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	// Verify current password
	if !user.CheckPassword(req.CurrentPassword) {
		utils.ErrorResponse(c, http.StatusUnauthorized, "incorrect current password")
		return
	}

	// Hash and set new password
	if err := user.SetPassword(req.NewPassword); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	// Save user
	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update password")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "password updated successfully",
	})
}

// CheckInit checks if the system needs initial setup (no users exist)
func (h *AuthHandler) CheckInit(c *gin.Context) {
	var count int64
	h.db.Model(&models.User{}).Count(&count)
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"initialized": count > 0,
	})
}

// InitializeRequest represents the request body for initial setup
type InitializeRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// Initialize creates the first admin user (only works when no users exist)
func (h *AuthHandler) Initialize(c *gin.Context) {
	// Check if system is already initialized
	var count int64
	h.db.Model(&models.User{}).Count(&count)
	if count > 0 {
		utils.ErrorResponse(c, http.StatusForbidden, "system is already initialized")
		return
	}

	var req InitializeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Create admin user
	user := &models.User{
		Username:    req.Username,
		Email:       req.Username + "@localhost",
		DisplayName: "Administrator",
		Role:        "admin",
		Status:      "active",
	}

	// Password is already MD5-hashed by the client (same as Login flow)
	if err := user.SetPassword(req.Password); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	if err := h.db.Create(user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create user")
		return
	}

	log.Printf("Initial admin user '%s' created via web setup from %s", req.Username, c.ClientIP())

	// Auto-login: generate tokens
	accessToken, refreshToken, err := h.generateTokens(user)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate tokens")
		return
	}

	// Update last login
	now := time.Now()
	user.LastLoginAt = &now
	h.db.Save(user)

	// Set cookie
	accessDuration, _ := time.ParseDuration(h.config.Security.AccessExpiration)
	if accessDuration == 0 {
		accessDuration = 60 * time.Minute
	}
	c.SetCookie("access_token", accessToken, int(accessDuration.Seconds()), "/", "", false, true)

	utils.SuccessResponse(c, http.StatusOK, LoginResponse{
		Token:        accessToken,
		RefreshToken: refreshToken,
		User:         user,
	})
}

// GetSystemInfo returns system information including version
// @Summary Get System Info
// @Description Returns system version information.
// @Tags System
// @Produce json
// @Success 200 {object} map[string]string "System Info"
// @Router /system/info [get]
func (h *AuthHandler) GetSystemInfo(c *gin.Context) {
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"version": config.Version,
	})
}

// autoAddOrigin automatically adds the request origin to allowed origins if valid
func (h *AuthHandler) autoAddOrigin(c *gin.Context) {
	origin := c.Request.Header.Get("Origin")

	// Skip if no Origin header (same-origin requests)
	if origin == "" {
		return
	}

	// Try to add the origin (will validate and deduplicate internally)
	if h.config.AddAllowedOrigin(origin) {
		// Successfully added, save to database
		if err := config.SaveAllowedOrigins(h.db, h.config.Server.AllowedOrigins); err != nil {
			utils.LogError("Failed to save allowed origin %s to database: %v", origin, err)
		} else {
			log.Printf("Auto-added origin to allowed list: %s", origin)
		}
	}
}

// ForgotPassword handles password reset request
// @Summary Forgot Password
// @Description Resets password and sends it to user's email
// @Tags Auth
// @Accept json
// @Produce json
// @Param request body struct{Email string} true "Email address"
// @Success 200 {object} map[string]string "Success message"
// @Failure 404 {object} map[string]string "User not found"
// @Router /auth/forgot-password [post]
func (h *AuthHandler) ForgotPassword(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var user models.User
	if err := h.db.Where("email = ?", req.Email).First(&user).Error; err != nil {
		// For security, do not return 404 if email not found, just success.
		// But for UX (specifically asked by user "处理忘记密码"), let's be explicit for now or just generic.
		// User requirement "用户可以通过邮箱获得一个随机的密码".
		// If email not found, we can't send email.
		// Let's use standard ambiguous response or just return error if internal.
		// For this project, clear feedback is likely preferred by the user unless specified.
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	// Generate temp password
	// 8 chars: 4 random bytes -> hex = 8 chars? No.
	// Simple random alphanumeric.
	tempPassword := utils.GenerateRandomString(8)

	// Hash it: MD5 -> Bcrypt
	// Client usually sends MD5. So we must treat this tempPassword as if client sent MD5(tempPassword).
	// So we compute MD5(tempPassword), then pass to SetPassword which does Bcrypt.
	md5Hash := md5.Sum([]byte(tempPassword))
	md5String := hex.EncodeToString(md5Hash[:])

	if err := user.SetPassword(md5String); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to set password")
		return
	}

	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update user")
		return
	}

	// Send notification (Email / Telegram) based on system settings
	var configs []models.SystemConfig
	if err := h.db.Find(&configs).Error; err != nil {
		// Log error but generally return success to user so they don't know it failed internally?
		// Actually, if we can't send email, they can't reset.
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to load system configuration")
		return
	}

	configMap := make(map[string]string)
	for _, c := range configs {
		configMap[c.ConfigKey] = c.ConfigValue
	}

	message := fmt.Sprintf("Hello,\n\n"+
		"You requested a password reset. Your temporary password is:\n\n"+
		"%s\n\n"+
		"Please login with this password and change it immediately using the 'Change Password' feature.\n\n"+
		"Best regards,\nTermiScope Team", tempPassword)

	subject := "TermiScope Password Reset"

	// Send Email if configured
	// Check minimal config presence
	// We use the system SMTP settings (Host, Port, User, Pass) but send TO the user's email (req.Email)
	if configMap["smtp_server"] != "" && configMap["smtp_from"] != "" {
		go func() {
			if err := utils.SendEmail(configMap, req.Email, subject, message); err != nil {
				log.Printf("Failed to send password reset email: %v", err)
			}
		}()
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "Password reset processed. If the email exists and notifications are configured, you will receive a message.",
	})
}
