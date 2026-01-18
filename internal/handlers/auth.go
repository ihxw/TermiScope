package handlers

import (
	"encoding/json"
	"log"
	"net/http"
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
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Find user by username or email
	var user models.User
	result := h.db.Where("username = ? OR email = ?", req.Username, req.Username).First(&user)
	if result.Error != nil {
		// Mitigate username enumeration
		bcrypt.CompareHashAndPassword([]byte("$2a$10$X7...dummyhash..."), []byte(req.Password))
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	// Check if user is active
	if !user.IsActive() {
		utils.ErrorResponse(c, http.StatusForbidden, "account is disabled")
		return
	}

	// Verify password
	if !user.CheckPassword(req.Password) {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	// Check if 2FA is enabled
	if user.TwoFactorEnabled {
		// Generate a temporary token for 2FA verification (short lived, e.g. 5 mins)
		tempToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "2fa_temp", 5*time.Minute, h.config.Security.JWTSecret)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate token")
			return
		}

		utils.SuccessResponse(c, http.StatusOK, gin.H{
			"requires_2fa": true,
			"temp_token":   tempToken,
			"user_id":      user.ID,
		})
		return
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

	// Auto-add origin if not already present (run in background)
	go h.autoAddOrigin(c)

	utils.SuccessResponse(c, http.StatusOK, LoginResponse{
		Token:        accessToken,
		RefreshToken: refreshToken,
		User:         &user,
	})
}

// RefreshToken handles token refresh
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	claims, err := utils.ValidateToken(req.RefreshToken, h.config.Security.JWTSecret)
	if err != nil {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid refresh token")
		return
	}

	if claims.TokenType != "refresh" {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid token type")
		return
	}

	// Check if user still exists and is active
	var user models.User
	if err := h.db.First(&user, claims.UserID).Error; err != nil || !user.IsActive() {
		utils.ErrorResponse(c, http.StatusUnauthorized, "user invalid")
		return
	}

	// Generate new access token
	accessExp, err := time.ParseDuration(h.config.Security.AccessExpiration)
	if err != nil {
		accessExp = 60 * time.Minute
	}

	accessToken, err := utils.GenerateToken(user.ID, user.Username, user.Role, "access", accessExp, h.config.Security.JWTSecret)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"token": accessToken,
	})
}

// Logout handles user logout
func (h *AuthHandler) Logout(c *gin.Context) {
	// In a stateless JWT system, logout is handled client-side
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "logged out successfully",
	})
}

// GetCurrentUser returns the current authenticated user
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
	username := middleware.GetUsername(c)
	role := middleware.GetRole(c)

	ticket := utils.GenerateTicket(userID, username, role)

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"ticket": ticket,
	})
}

type Verify2FALoginRequest struct {
	UserID uint   `json:"user_id" binding:"required"`
	Code   string `json:"code" binding:"required"`
}

// Verify2FALogin verifies 2FA code and completes login
func (h *AuthHandler) Verify2FALogin(c *gin.Context) {
	var req Verify2FALoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
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

// GetSystemInfo returns system information including version
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
log.Printf("Failed to save allowed origin %s to database: %v", origin, err)
} else {
log.Printf("Auto-added origin to allowed list: %s", origin)
}
}
}
