package handlers

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image/png"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type TwoFactorHandler struct {
	db            *gorm.DB
	encryptionKey string
}

func NewTwoFactorHandler(db *gorm.DB, encryptionKey string) *TwoFactorHandler {
	return &TwoFactorHandler{
		db:            db,
		encryptionKey: encryptionKey,
	}
}

type SetupResponse struct {
	Secret string `json:"secret"`
	QRCode string `json:"qr_code"` // Base64 encoded PNG
	URL    string `json:"url"`
}

type VerifyRequest struct {
	Code string `json:"code" binding:"required"`
}

type BackupCodesResponse struct {
	Codes []string `json:"codes"`
}

// Setup2FA generates a new TOTP secret and QR code
func (h *TwoFactorHandler) Setup2FA(c *gin.Context) {
	userID := middleware.GetUserID(c)
	username := middleware.GetUsername(c)

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	// Generate TOTP key
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      "TermiScope",
		AccountName: username,
		SecretSize:  32,
	})
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate 2FA secret")
		return
	}

	// Generate QR code
	var buf bytes.Buffer
	img, err := key.Image(256, 256)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to generate QR code")
		return
	}
	if err := png.Encode(&buf, img); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encode QR code")
		return
	}

	// Encode QR code to base64
	qrCode := base64.StdEncoding.EncodeToString(buf.Bytes())

	utils.SuccessResponse(c, http.StatusOK, SetupResponse{
		Secret: key.Secret(),
		QRCode: "data:image/png;base64," + qrCode,
		URL:    key.URL(),
	})
}

// VerifySetup2FA verifies the TOTP code and enables 2FA
func (h *TwoFactorHandler) VerifySetup2FA(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	// Get the secret from session or temporary storage
	// For simplicity, we'll expect the secret to be sent in the request
	secret := c.GetHeader("X-2FA-Secret")
	if secret == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "2FA secret not found")
		return
	}

	// Verify the code
	valid := totp.Validate(req.Code, secret)
	if !valid {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid verification code")
		return
	}

	// Encrypt and save the secret
	encryptedSecret, err := utils.Encrypt(secret, h.encryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt secret")
		return
	}

	// Generate 1 backup code
	backupCodes := generateBackupCodes(1)
	hashedCodes := make([]string, len(backupCodes))
	for i, code := range backupCodes {
		hash, _ := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
		hashedCodes[i] = string(hash)
	}

	backupCodesJSON, _ := json.Marshal(hashedCodes)
	encryptedBackupCodes, err := utils.Encrypt(string(backupCodesJSON), h.encryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt backup codes")
		return
	}

	// Update user
	user.TwoFactorEnabled = true
	user.TwoFactorSecret = encryptedSecret
	user.BackupCodes = encryptedBackupCodes

	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to enable 2FA")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, BackupCodesResponse{
		Codes: backupCodes,
	})
}

// Disable2FA disables two-factor authentication
func (h *TwoFactorHandler) Disable2FA(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	if !user.TwoFactorEnabled {
		utils.ErrorResponse(c, http.StatusBadRequest, "2FA is not enabled")
		return
	}

	// Decrypt secret
	secret, err := utils.Decrypt(user.TwoFactorSecret, h.encryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to decrypt secret")
		return
	}

	// Verify the code
	valid := totp.Validate(req.Code, secret)
	if !valid {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid verification code")
		return
	}

	// Disable 2FA
	user.TwoFactorEnabled = false
	user.TwoFactorSecret = ""
	user.BackupCodes = ""

	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to disable 2FA")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "2FA disabled successfully",
	})
}

// Verify2FA verifies a TOTP code during login
func (h *TwoFactorHandler) Verify2FA(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req VerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	if !user.TwoFactorEnabled {
		utils.ErrorResponse(c, http.StatusBadRequest, "2FA is not enabled")
		return
	}

	// Decrypt secret
	secret, err := utils.Decrypt(user.TwoFactorSecret, h.encryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to decrypt secret")
		return
	}

	// Verify the code
	valid := totp.Validate(req.Code, secret)
	if !valid {
		// Check backup codes
		if !h.verifyBackupCode(req.Code, user.BackupCodes) {
			utils.ErrorResponse(c, http.StatusBadRequest, "invalid verification code")
			return
		}
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "verification successful",
	})
}

// RegenerateBackupCodes generates new backup codes
func (h *TwoFactorHandler) RegenerateBackupCodes(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	if !user.TwoFactorEnabled {
		utils.ErrorResponse(c, http.StatusBadRequest, "2FA is not enabled")
		return
	}

	// Generate 1 new backup code
	backupCodes := generateBackupCodes(1)
	hashedCodes := make([]string, len(backupCodes))
	for i, code := range backupCodes {
		hash, _ := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
		hashedCodes[i] = string(hash)
	}

	backupCodesJSON, _ := json.Marshal(hashedCodes)
	encryptedBackupCodes, err := utils.Encrypt(string(backupCodesJSON), h.encryptionKey)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt backup codes")
		return
	}

	user.BackupCodes = encryptedBackupCodes
	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to save backup codes")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, BackupCodesResponse{
		Codes: backupCodes,
	})
}

// Helper functions

func generateBackupCodes(count int) []string {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	codes := make([]string, count)

	for i := 0; i < count; i++ {
		// Generate 32 random characters
		code := make([]byte, 32)
		for j := range code {
			randomByte := make([]byte, 1)
			if _, err := rand.Read(randomByte); err != nil {
				// Fallback to a simple random if crypto fails
				code[j] = charset[i*j%len(charset)]
			} else {
				code[j] = charset[int(randomByte[0])%len(charset)]
			}
		}

		formatted := fmt.Sprintf("%s-%s-%s-%s",
			string(code[0:8]),
			string(code[8:16]),
			string(code[16:24]),
			string(code[24:32]),
		)
		codes[i] = formatted
	}

	return codes
}

func (h *TwoFactorHandler) verifyBackupCode(code, encryptedCodes string) bool {
	if encryptedCodes == "" {
		return false
	}

	decrypted, err := utils.Decrypt(encryptedCodes, h.encryptionKey)
	if err != nil {
		return false
	}

	var hashedCodes []string
	if err := json.Unmarshal([]byte(decrypted), &hashedCodes); err != nil {
		return false
	}

	for _, hash := range hashedCodes {
		if bcrypt.CompareHashAndPassword([]byte(hash), []byte(code)) == nil {
			return true
		}
	}

	return false
}
