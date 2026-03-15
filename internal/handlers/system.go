package handlers

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/updater"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
	"sync"
)

type SystemHandler struct {
	db      *gorm.DB
	config  *config.Config
	version string
}

var (
	serverUpdateStatus string
	serverUpdateError  string
	serverUpdateMu     sync.Mutex
)

func setServerUpdateStatus(status, errStr string) {
	serverUpdateMu.Lock()
	defer serverUpdateMu.Unlock()
	serverUpdateStatus = status
	serverUpdateError = errStr
}

func NewSystemHandler(db *gorm.DB, cfg *config.Config, version string) *SystemHandler {
	return &SystemHandler{
		db:      db,
		config:  cfg,
		version: version,
	}
}

// isValidPath validates that a path contains only safe characters
// and doesn't contain path traversal sequences
func isValidPath(path string) bool {
	// Check for path traversal attempts
	if matched, _ := regexp.MatchString(`\.\.`, path); matched {
		return false
	}
	// Only allow alphanumeric, dash, underscore, dot, and path separators
	validPattern := regexp.MustCompile(`^[a-zA-Z0-9_\-./\\:]+$`)
	return validPattern.MatchString(path)
}

// Backup handles database backup generation
func (h *SystemHandler) Backup(c *gin.Context) {
	dbPath := h.config.Database.Path

	var req struct {
		Password string `json:"password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		// Ignore bind error
	}
	password := req.Password

	// Clean up old backups (older than 1 hour)
	tmpDir := os.TempDir()
	files, _ := filepath.Glob(filepath.Join(tmpDir, "termiscope_backup_*"))
	for _, f := range files {
		info, err := os.Stat(f)
		if err == nil && time.Since(info.ModTime()) > time.Hour {
			os.Remove(f)
		}
	}

	// Create a temporary backup file
	// Use consistent naming scheme we can validate later
	timestamp := time.Now().Format("20060102_150405")
	fileName := fmt.Sprintf("termiscope_backup_%s.db", timestamp)
	if password != "" {
		fileName += ".enc"
	}
	tmpBackup := filepath.Join(tmpDir, fileName)

	// Use SQLite's VACUUM INTO for a consistent backup
	// Note: For encrypted backups, we first vacuum to a temp .db then encrypt.
	// But to simplify, let's keep the logic close to original but split steps.

	// Intermediate file for vacuum (always .db)
	vacuumFile := filepath.Join(tmpDir, fmt.Sprintf("termiscope_vacuum_%s.db", timestamp))

	if err := h.db.Exec("VACUUM INTO ?", vacuumFile).Error; err != nil {
		fmt.Printf("VACUUM INTO failed: %v. Output path: %s\n", err, vacuumFile)
		// Fallback copy
		if copyErr := copyFile(dbPath, vacuumFile); copyErr != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, fmt.Sprintf("failed to create backup: %v", err))
			return
		}
	}

	finalPath := tmpBackup

	if password != "" {
		// Encrypt vacuumFile -> tmpBackup (which has .enc)
		if err := utils.EncryptFile(vacuumFile, tmpBackup, password); err != nil {
			os.Remove(vacuumFile)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt backup: "+err.Error())
			return
		}
		os.Remove(vacuumFile) // Remove unencrypted intermediate
	} else {
		// Just rename vacuumFile to finalPath
		if err := os.Rename(vacuumFile, finalPath); err != nil {
			os.Remove(vacuumFile)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to rename backup: "+err.Error())
			return
		}
	}

	// Generate one-time ticket for download
	userID := middleware.GetUserID(c)
	username := middleware.GetUsername(c)
	role := middleware.GetRole(c)
	ticket := utils.GenerateTicket(userID, username, role)

	// Return the filename and ticket to frontend
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data": gin.H{
			"filename": fileName,
			"ticket":   ticket,
		},
	})
}

// DownloadBackup serves the backup file
func (h *SystemHandler) DownloadBackup(c *gin.Context) {
	filename := c.Query("file")
	if filename == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "filename required")
		return
	}

	// Strict validation: basic alphanumeric + dots, must start with termiscope_backup_
	if matched, _ := regexp.MatchString(`^termiscope_backup_[a-zA-Z0-9_.]+\.(db|enc)$`, filename); !matched {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid filename")
		return
	}

	tmpDir := os.TempDir()
	filePath := filepath.Join(tmpDir, filename)

	// Verify existence
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		utils.ErrorResponse(c, http.StatusNotFound, "backup file not found or expired")
		return
	}

	c.Header("Content-Description", "File Transfer")
	c.Header("Content-Transfer-Encoding", "binary")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Type", "application/octet-stream")
	c.File(filePath)
}

// Restore handles database restoration from uploaded file
func (h *SystemHandler) Restore(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "no file uploaded")
		return
	}
	password := c.PostForm("password")

	// Basic validation: check file extension
	if filepath.Ext(file.Filename) != ".db" {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid file type, must be .db")
		return
	}

	// Save uploaded file to temporary location
	tmpFile := filepath.Join(os.TempDir(), "termiscope_restore.db")
	if err := c.SaveUploadedFile(file, tmpFile); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to save uploaded file")
		return
	}
	defer os.Remove(tmpFile)

	targetFile := tmpFile

	// If password provided, attempt decryption
	if password != "" {
		tmpDecFile := tmpFile + ".dec"
		if err := utils.DecryptFile(tmpFile, tmpDecFile, password); err != nil {
			utils.ErrorResponse(c, http.StatusForbidden, "incorrect password")
			return
		}
		defer os.Remove(tmpDecFile)
		targetFile = tmpDecFile
	}

	// Close current DB connections before replacing the file
	sqlDB, err := h.db.DB()
	if err == nil {
		sqlDB.Close()
	}

	// Replace the current database file
	dbPath := h.config.Database.Path
	if err := copyFile(targetFile, dbPath); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to restore database file: "+err.Error())
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "database restored successfully, server is restarting...",
	})

	// Restart server to reload database
	go func() {
		// Attempt to spawn the restarter script
		if err := utils.RestartSelf(); err != nil {
			// If we can't restart, at least we log it. The process will still exit,
			// forcing a manual restart which is better than undefined state.
			utils.LogError("Failed to initiate self-restart: %v", err)
		}

		// Give the response a moment to flush
		time.Sleep(1 * time.Second)
		os.Exit(0)
	}()
}

func copyFile(src, dst string) error {
	sourceFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sourceFile.Close()

	destFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer destFile.Close()

	_, err = io.Copy(destFile, sourceFile)
	if err != nil {
		return err
	}

	return destFile.Sync()
}

// GetSettings returns current editable settings
func (h *SystemHandler) GetSettings(c *gin.Context) {
	// Fetch notification settings from DB
	var configs []models.SystemConfig
	h.db.Where("config_key LIKE ? OR config_key LIKE ? OR config_key = ?", "smtp_%", "telegram_%", "notification_template").Find(&configs)

	settings := gin.H{
		"timezone":                 h.config.Server.Timezone,
		"ssh_timeout":              h.config.SSH.Timeout,
		"idle_timeout":             h.config.SSH.IdleTimeout,
		"max_connections_per_user": h.config.SSH.MaxConnectionsPerUser,
		"login_rate_limit":         h.config.Security.LoginRateLimit,
		"access_expiration":        h.config.Security.AccessExpiration,
		"refresh_expiration":       h.config.Security.RefreshExpiration,
	}

	for _, cfg := range configs {
		settings[cfg.ConfigKey] = cfg.ConfigValue
	}

	utils.SuccessResponse(c, http.StatusOK, settings)
}

// UpdateSettingsRequest defines the request body for updating settings
type UpdateSettingsRequest struct {
	Timezone              string `json:"timezone" binding:"required"`
	SSHTimeout            string `json:"ssh_timeout" binding:"required"`
	IdleTimeout           string `json:"idle_timeout" binding:"required"`
	MaxConnectionsPerUser int    `json:"max_connections_per_user" binding:"required"`
	LoginRateLimit        int    `json:"login_rate_limit" binding:"required"`
	AccessExpiration      string `json:"access_expiration" binding:"required"`
	RefreshExpiration     string `json:"refresh_expiration" binding:"required"`
	// Notification Settings (Optional)
	SMTPServer           string `json:"smtp_server"`
	SMTPPort             string `json:"smtp_port"`
	SMTPUser             string `json:"smtp_user"`
	SMTPPassword         string `json:"smtp_password"`
	SMTPFrom             string `json:"smtp_from"`
	SMTPTo               string `json:"smtp_to"`
	TelegramBotToken     string `json:"telegram_bot_token"`
	TelegramChatID       string `json:"telegram_chat_id"`
	NotificationTemplate string `json:"notification_template"`
}

// Global rate limiter reference for dynamic updates
var LoginRateLimiter *middleware.RateLimiter

// UpdateSettings updates configuration and persists to file
func (h *SystemHandler) UpdateSettings(c *gin.Context) {
	var req UpdateSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Validate duration formats
	if _, err := time.ParseDuration(req.AccessExpiration); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid access_expiration format (e.g. 60m, 1h)")
		return
	}
	if _, err := time.ParseDuration(req.RefreshExpiration); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid refresh_expiration format (e.g. 168h)")
		return
	}
	if _, err := time.ParseDuration(req.SSHTimeout); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid ssh_timeout format (e.g. 30s)")
		return
	}
	if _, err := time.ParseDuration(req.IdleTimeout); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid idle_timeout format (e.g. 30m)")
		return
	}

	// Update DB (Transaction)
	err := h.db.Transaction(func(tx *gorm.DB) error {
		updates := map[string]string{
			"server.timezone":              req.Timezone,
			"ssh.timeout":                  req.SSHTimeout,
			"ssh.idle_timeout":             req.IdleTimeout,
			"ssh.max_connections_per_user": fmt.Sprintf("%d", req.MaxConnectionsPerUser),
			"security.login_rate_limit":    fmt.Sprintf("%d", req.LoginRateLimit),
			"security.access_expiration":   req.AccessExpiration,
			"security.refresh_expiration":  req.RefreshExpiration,
			// Notification
			"smtp_server":           req.SMTPServer,
			"smtp_port":             req.SMTPPort,
			"smtp_user":             req.SMTPUser,
			"smtp_password":         req.SMTPPassword,
			"smtp_from":             req.SMTPFrom,
			"smtp_to":               req.SMTPTo,
			"telegram_bot_token":    req.TelegramBotToken,
			"telegram_chat_id":      req.TelegramChatID,
			"notification_template": req.NotificationTemplate,
		}

		for key, value := range updates {
			// Upsert Logic
			var count int64
			tx.Model(&models.SystemConfig{}).Where("config_key = ?", key).Count(&count)
			if count == 0 {
				// Create
				if err := tx.Create(&models.SystemConfig{ConfigKey: key, ConfigValue: value}).Error; err != nil {
					return err
				}
			} else {
				// Update
				if err := tx.Model(&models.SystemConfig{}).Where("config_key = ?", key).Update("config_value", value).Error; err != nil {
					return err
				}
			}
		}
		return nil
	})

	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to save configuration to database: "+err.Error())
		return
	}

	// Update in-memory config
	h.config.Server.Timezone = req.Timezone
	if req.Timezone != "" && req.Timezone != "Local" {
		loc, err := time.LoadLocation(req.Timezone)
		if err == nil {
			time.Local = loc
		}
	} else if req.Timezone == "Local" {
		time.Local = time.Now().Location()
	}
	h.config.SSH.Timeout = req.SSHTimeout
	h.config.SSH.IdleTimeout = req.IdleTimeout
	h.config.SSH.MaxConnectionsPerUser = req.MaxConnectionsPerUser
	h.config.Security.LoginRateLimit = req.LoginRateLimit
	h.config.Security.AccessExpiration = req.AccessExpiration
	h.config.Security.RefreshExpiration = req.RefreshExpiration

	// Hot-reload rate limit if global limiter is set
	if LoginRateLimiter != nil {
		LoginRateLimiter.SetLimit(req.LoginRateLimit)
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "settings updated successfully",
	})
}

// GetAgentVersion returns the current agent version
func (h *SystemHandler) GetAgentVersion(c *gin.Context) {
	// Version is injected during build
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"version": h.version,
	})
}

// CheckUpdate checks for available updates
func (h *SystemHandler) CheckUpdate(c *gin.Context) {
	updateInfo, err := updater.CheckForUpdate(h.version)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "Failed to check for updates: "+err.Error())
		return
	}

	if updateInfo == nil {
		utils.SuccessResponse(c, http.StatusOK, gin.H{
			"update_available": false,
		})
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"update_available": true,
		"version":          updateInfo.Version,
		"body":             updateInfo.Body,
		"download_url":     updateInfo.DownloadURL,
		"size":             updateInfo.Size,
	})
}

// PerformUpdate executes the update process
func (h *SystemHandler) PerformUpdate(c *gin.Context) {
	var req struct {
		DownloadURL string `json:"download_url" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "Invalid request: "+err.Error())
		return
	}

	setServerUpdateStatus("starting", "")

	// Run update in background to not block response
	go func() {
		statusCallback := func(status string) {
			setServerUpdateStatus(status, "")
			utils.LogError("Server update status: %s", status)
		}

		if err := updater.PerformUpdate(req.DownloadURL, statusCallback); err != nil {
			setServerUpdateStatus("error", err.Error())
			utils.LogError("Update failed: %v", err)
		} else {
			setServerUpdateStatus("restarting", "")
			utils.LogError("Update successful, restarting...")
		}
	}()

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "Update initiated. Server will restart shortly.",
	})
}

// GetUpdateStatus API lets frontend poll for server update process status
func (h *SystemHandler) GetUpdateStatus(c *gin.Context) {
	serverUpdateMu.Lock()
	defer serverUpdateMu.Unlock()
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"status": serverUpdateStatus,
		"error":  serverUpdateError,
	})
}

// TestEmail handles test email sending
func (h *SystemHandler) TestEmail(c *gin.Context) {
	var req struct {
		SMTPServer     string `json:"smtp_server"`
		SMTPPort       string `json:"smtp_port"`
		SMTPUser       string `json:"smtp_user"`
		SMTPPassword   string `json:"smtp_password"`
		SMTPFrom       string `json:"smtp_from"`
		SMTPTo         string `json:"smtp_to"`
		SMTPSkipVerify bool   `json:"smtp_tls_skip_verify"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	configMap := map[string]string{
		"smtp_server":          req.SMTPServer,
		"smtp_port":            req.SMTPPort,
		"smtp_user":            req.SMTPUser,
		"smtp_password":        req.SMTPPassword,
		"smtp_from":            req.SMTPFrom,
		"smtp_to":              req.SMTPTo,
		"smtp_tls_skip_verify": fmt.Sprintf("%v", req.SMTPSkipVerify),
	}

	// Use existing config if specific fields are missing (optional convenience)
	// But usually, testing uses the form data. Let's stick to using what is sent,
	// or fallback to DB if empty?
	// The requirement implies testing the *current* settings in the UI form.
	// So we should rely on the request body.

	err := utils.SendEmail(configMap, req.SMTPTo, "TermiScope Test Email", "This is a test email from TermiScope.")
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "Failed to send email: "+err.Error())
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "Test email sent successfully",
	})
}

// TestTelegram handles test telegram message sending
func (h *SystemHandler) TestTelegram(c *gin.Context) {
	var req struct {
		TelegramBotToken string `json:"telegram_bot_token"`
		TelegramChatID   string `json:"telegram_chat_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	configMap := map[string]string{
		"telegram_bot_token": req.TelegramBotToken,
		"telegram_chat_id":   req.TelegramChatID,
	}

	err := utils.SendTelegram(configMap, "This is a test message from *TermiScope*.")
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "Failed to send telegram: "+err.Error())
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "Test telegram sent successfully",
	})
}
