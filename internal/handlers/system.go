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
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type SystemHandler struct {
	db      *gorm.DB
	config  *config.Config
	version string
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

// Backup handles database backup download
func (h *SystemHandler) Backup(c *gin.Context) {
	dbPath := h.config.Database.Path
	password := c.Query("password")

	// Create a temporary backup file to avoid locking the main DB during download
	tmpBackup := filepath.Join(os.TempDir(), fmt.Sprintf("termiscope_backup_%d.db", time.Now().Unix()))

	// Validate tmpBackup path (defense in depth - ensure no SQL injection)
	if !isValidPath(tmpBackup) {
		utils.ErrorResponse(c, http.StatusInternalServerError, "invalid backup path")
		return
	}

	// Use SQLite's VACUUM INTO for a consistent backup
	// Use parameterized query to prevent SQL injection
	err := h.db.Exec("VACUUM INTO ?", tmpBackup).Error
	if err != nil {
		// Fallback to simple file copy if VACUUM INTO fails (e.g. older SQLite)
		err = copyFile(dbPath, tmpBackup)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create backup: "+err.Error())
			return
		}
	}
	defer os.Remove(tmpBackup)

	finalFile := tmpBackup
	downloadName := fmt.Sprintf("termiscope_backup_%s.db", time.Now().Format("20060102_150405"))

	// If password is provided, encrypt the backup
	if password != "" {
		tmpEncBackup := tmpBackup + ".enc"
		if err := utils.EncryptFile(tmpBackup, tmpEncBackup, password); err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt backup: "+err.Error())
			return
		}
		defer os.Remove(tmpEncBackup)
		finalFile = tmpEncBackup
		// Reflect encryption in filename, though strictly not necessary if we auto-detect on restore
		// keeping .db extension but maybe adding _enc suffix is clearer
		downloadName = fmt.Sprintf("termiscope_backup_enc_%s.db", time.Now().Format("20060102_150405"))
	}

	c.Header("Content-Description", "File Transfer")
	c.Header("Content-Transfer-Encoding", "binary")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", downloadName))
	c.Header("Content-Type", "application/octet-stream")
	c.File(finalFile)
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
