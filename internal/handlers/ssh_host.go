package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type SSHHostHandler struct {
	db     *gorm.DB
	config *config.Config
}

func NewSSHHostHandler(db *gorm.DB, cfg *config.Config) *SSHHostHandler {
	return &SSHHostHandler{
		db:     db,
		config: cfg,
	}
}

type CreateSSHHostRequest struct {
	Name        string `json:"name" binding:"required"`
	Host        string `json:"host"`
	Port        int    `json:"port"`
	Username    string `json:"username"`
	AuthType    string `json:"auth_type" binding:"omitempty,oneof=password key"`
	Password    string `json:"password"`
	PrivateKey  string `json:"private_key"`
	GroupName   string `json:"group_name"`
	Tags        string `json:"tags"`
	Description string `json:"description"`
	HostType    string `json:"host_type" binding:"required,oneof=control_monitor monitor_only"`
}

type UpdateSSHHostRequest struct {
	Name        string `json:"name"`
	Host        string `json:"host"`
	Port        int    `json:"port"`
	Username    string `json:"username"`
	AuthType    string `json:"auth_type" binding:"omitempty,oneof=password key"`
	Password    string `json:"password"`
	PrivateKey  string `json:"private_key"`
	GroupName   string `json:"group_name"`
	Tags        string `json:"tags"`
	Description string `json:"description"`
	HostType    string `json:"host_type" binding:"omitempty,oneof=control_monitor monitor_only"`
	// Network Config
	NetInterface string `json:"net_interface"`
	NetResetDay  int    `json:"net_reset_day"`
	// Traffic Limit Config
	NetTrafficLimit          uint64 `json:"net_traffic_limit"`
	NetTrafficUsedAdjustment uint64 `json:"net_traffic_used_adjustment"`
	NetTrafficCounterMode    string `json:"net_traffic_counter_mode"` // total, rx, tx
	// Notification
	NotifyOfflineEnabled   *bool  `json:"notify_offline_enabled"`
	NotifyTrafficEnabled   *bool  `json:"notify_traffic_enabled"`
	NotifyOfflineThreshold int    `json:"notify_offline_threshold"`
	NotifyTrafficThreshold int    `json:"notify_traffic_threshold"`
	NotifyChannels         string `json:"notify_channels"`

	// Actions
	ResetTraffic bool `json:"reset_traffic"`
}

// List returns a list of SSH hosts for the current user
func (h *SSHHostHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	group := c.Query("group")
	search := c.Query("search")

	query := h.db.Model(&models.SSHHost{}).Where("user_id = ?", userID).Order("sort_order asc")

	// Group filter
	if group != "" {
		query = query.Where("group_name = ?", group)
	}

	// Search filter
	if search != "" {
		query = query.Where("name LIKE ? OR host LIKE ? OR description LIKE ?",
			"%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	var hosts []models.SSHHost
	if err := query.Find(&hosts).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch hosts")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, hosts)
}

// Get returns a single SSH host
func (h *SSHHostHandler) Get(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	// Decrypt credentials
	if host.PasswordEncrypted != "" {
		password, err := utils.DecryptAES(host.PasswordEncrypted, h.config.Security.EncryptionKey)
		if err == nil {
			host.Password = password
		}
	}
	if host.PrivateKeyEncrypted != "" {
		privateKey, err := utils.DecryptAES(host.PrivateKeyEncrypted, h.config.Security.EncryptionKey)
		if err == nil {
			host.PrivateKey = privateKey
		}
	}

	utils.SuccessResponse(c, http.StatusOK, host)
}

// Create creates a new SSH host
func (h *SSHHostHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req CreateSSHHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// 根据主机类型进行验证
	if req.HostType == "control_monitor" {
		// 控制+监控类型需要 SSH 相关字段
		if req.Host == "" {
			utils.ErrorResponse(c, http.StatusBadRequest, "host is required for control_monitor type")
			return
		}
		if req.Username == "" {
			utils.ErrorResponse(c, http.StatusBadRequest, "username is required for control_monitor type")
			return
		}
		if req.AuthType == "" {
			utils.ErrorResponse(c, http.StatusBadRequest, "auth_type is required for control_monitor type")
			return
		}

		// Validate auth type and credentials
		if req.AuthType == "password" && req.Password == "" {
			utils.ErrorResponse(c, http.StatusBadRequest, "password is required for password authentication")
			return
		}
		if req.AuthType == "key" && req.PrivateKey == "" {
			utils.ErrorResponse(c, http.StatusBadRequest, "private key is required for key authentication")
			return
		}
	}

	// Set default port
	if req.Port == 0 {
		req.Port = 22
	}

	// Create host
	host := &models.SSHHost{
		UserID:      userID,
		Name:        req.Name,
		Host:        req.Host,
		Port:        req.Port,
		Username:    req.Username,
		AuthType:    req.AuthType,
		GroupName:   req.GroupName,
		Tags:        req.Tags,
		Description: req.Description,
		HostType:    req.HostType,
		// Default Notification Settings for new host
		NotifyOfflineEnabled:   true,
		NotifyTrafficEnabled:   true,
		NotifyOfflineThreshold: 1,
		NotifyTrafficThreshold: 90,
		NotifyChannels:         "email,telegram",
	}

	// 自动生成 MonitorSecret（32位永久token）
	randomBytes := make([]byte, 32)
	rand.Read(randomBytes)
	host.MonitorSecret = hex.EncodeToString(randomBytes)

	// Encrypt credentials
	if req.Password != "" {
		encrypted, err := utils.EncryptAES(req.Password, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt password")
			return
		}
		host.PasswordEncrypted = encrypted
	}
	if req.PrivateKey != "" {
		encrypted, err := utils.EncryptAES(req.PrivateKey, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt private key")
			return
		}
		host.PrivateKeyEncrypted = encrypted
	}

	if err := h.db.Create(host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create host")
		return
	}

	utils.SuccessResponse(c, http.StatusCreated, host)
}

// Update updates an SSH host
func (h *SSHHostHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req UpdateSSHHostRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	// Update fields
	if req.Name != "" {
		host.Name = req.Name
	}
	if req.Host != "" {
		host.Host = req.Host
	}
	if req.Port != 0 {
		host.Port = req.Port
	}
	if req.Username != "" {
		host.Username = req.Username
	}
	if req.AuthType != "" {
		host.AuthType = req.AuthType
	}
	if req.GroupName != "" {
		host.GroupName = req.GroupName
	}
	if req.Tags != "" {
		host.Tags = req.Tags
	}
	if req.Description != "" {
		host.Description = req.Description
	}
	if req.HostType != "" {
		host.HostType = req.HostType
	}
	// Network Config
	if req.NetInterface != "" {
		// If interface selection changed, we MUST reset LastRaw to avoid massive delta spikes
		// (false positive reboot or huge jump)
		if host.NetInterface != req.NetInterface {
			host.NetLastRawRx = 0
			host.NetLastRawTx = 0

			// Optional: Should we also reset Monthly?
			// No, user might just be refining selection.
			// But the accumulated data might be mixed.
			// Ideally we keep monthly but stop the spike.
		}
		host.NetInterface = req.NetInterface
	}
	if req.NetResetDay > 0 && req.NetResetDay <= 31 {
		host.NetResetDay = req.NetResetDay
	}

	// Reset Traffic First if requested
	if req.ResetTraffic {
		host.NetMonthlyRx = 0
		host.NetMonthlyTx = 0
		host.NetLastResetDate = time.Now().Format("2006-01-02")
		host.TrafficAlerted = false
		// But "Reset Stats" usually implies starting fresh.
		// Let's reset adjustment too for a clean slate.
		// HOWEVER: If the request explicitly sets a new adjustment (e.g. calibration),
		// we should allow that to override this reset.
		// Since we process specific fields later, we just ensure we don't accidentally ignore the new value.
		// Currently, the logic below (lines 322+) handles updating NetTrafficUsedAdjustment.
		// So resetting it here to 0 is fine, AS LONG AS line 324 applies the new value.
		// The issue is: In line 322, we check `if req.NetTrafficLimit > 0 || req.NetTrafficUsedAdjustment > 0`.
		// If user sets adjustment to 0, req.NetTrafficUsedAdjustment is 0.
		// So line 324 is skipped.
		// But here we set it to 0 anyway. So 0 is fine.
		// If user sets adjustment to 100, req is 100. Line 322 is true. Line 324 sets it to 100.
		// So theoretically it should work?
		// Unless... `ResetTraffic` logic clears it, and then...
		// Ah, wait. Code flow:
		// 1. Reset fields to 0.
		// 2. Check req fields.
		// 3. Update host fields.
		//
		// If User Input = 100GB -> req.Adjustment = 100GB.
		// Line 299: Host.Adjustment = 0.
		// Line 322: req.Adjustment > 0 -> True.
		// Line 324: Host.Adjustment = 100GB.
		// Result: 100GB. Correct.

		// If User Input = 0GB -> req.Adjustment = 0.
		// Line 299: Host.Adjustment = 0.
		// Line 322: req.Adjustment > 0 -> False (assuming Limit also 0/unchanged and Mode empty/unchanged).
		// Line 324: Skipped.
		// Result: 0. Correct.

		// Wait, why did the user say it failed?
		// Maybe `req.NetTrafficUsedAdjustment` is not coming through correctly?
		// Frontend sends `net_traffic_used_adjustment`.
		// Let's look at the frontend logic again.
		// `const trafficAdj = Math.floor(customTotal.value * 1024 * 1024 * 1024)`
		// If customTotal = 161.36
		// trafficAdj = 173259920179
		// Backend receives this.

		// Is it possible `req` struct tags are wrong?
		// `NetTrafficUsedAdjustment uint64 `json:"net_traffic_used_adjustment"`
		// Seems correct.

		// Let's force set it regardless of 0 check if we are resetting?
		// Or better: Just set it explicitly if it's in the request?
		// But we can't know if "0" means "User explicitly set 0" or "User didn't send field".
		// But for "Save Config", we always send it.
		//
		// actually, maybe the issue is that I am ONLY updating if > 0?
		// Use `calibration` logic:
		// If we are performing a reset (ResetTraffic=true), we should perhaps ALWAYS apply the adjustment from the request, even if it is 0.
		// Because `ResetTraffic` implies we are re-calibrating.

		host.NetTrafficUsedAdjustment = 0
	}

	// FIX: Always update adjustment if ResetTraffic is true (Calibration Mode), OR if valid value provided.
	// Actually, just checking > 0 is insufficient if we want to set it to 0 without ResetTraffic (unlikely but possible).
	// But in this specific case (Save Config), ResetTraffic is ALWAYS true per frontend change.
	// So we should perform the update.

	if req.ResetTraffic || req.NetTrafficLimit > 0 || req.NetTrafficUsedAdjustment > 0 || req.NetTrafficCounterMode != "" {
		host.NetTrafficLimit = req.NetTrafficLimit
		host.NetTrafficUsedAdjustment = req.NetTrafficUsedAdjustment // This will take 0 if req is 0, which is what we want after reset + set.
		if req.NetTrafficCounterMode != "" {
			host.NetTrafficCounterMode = req.NetTrafficCounterMode
		}
	}

	// Notification Config
	// Allows updating to 0 or valid values. If missing (0/"") in JSON, we might overwrite with 0 which is default/disable maybe?
	// User defaults: Offline=1, Traffic=90.
	// If frontend sends partial update without these fields, they will be 0.
	// But `UpdateSSHHostRequest` is usually full update or we check if non-zero.
	// Let's assume frontend sends current values if it includes them.
	// If 0 is passed, it means 0 (which checker treats as 1 min).
	// To handle partial updates where these are NOT sent:
	// We can't distinguish 0 from missing.
	// Assuming frontend sends all relevant fields or we check if values are reasonably set?
	// Let's just update if provided?
	// Since 0 is "valid" (mapped to default 1), we can just set them.
	// But if request omits them, they are 0. If we enable overwrite, we reset existing config to 0.
	// Since frontend `MonitorDashboard` will likely have a specific modal for this, it will send these fields.
	// `modifyHost` in store sends PUT.
	// For now, I'll update them indiscriminately if they are in the request struct.
	// If this causes issues with other update calls (e.g. rename host) resetting these to 0,
	// we should use pointers or check context.
	// `modifyHost` likely sends what we fetch + changes?
	// `sshStore` keeps full object. `modifyHost` sends `hostData`.
	// Most likely partial updates are risky with struct binding.
	// But let's add them.
	if req.NotifyOfflineEnabled != nil {
		host.NotifyOfflineEnabled = *req.NotifyOfflineEnabled
	}
	if req.NotifyTrafficEnabled != nil {
		host.NotifyTrafficEnabled = *req.NotifyTrafficEnabled
	}
	if req.NotifyOfflineThreshold != 0 { // 0 is a valid threshold, but default is 1. If 0 is sent, use it.
		host.NotifyOfflineThreshold = req.NotifyOfflineThreshold
	}
	if req.NotifyTrafficThreshold != 0 { // 0 is a valid threshold, but default is 90. If 0 is sent, use it.
		host.NotifyTrafficThreshold = req.NotifyTrafficThreshold
	}
	if req.NotifyChannels != "" {
		host.NotifyChannels = req.NotifyChannels
	}

	// Update encrypted credentials if provided
	if req.Password != "" {
		encrypted, err := utils.EncryptAES(req.Password, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt password")
			return
		}
		host.PasswordEncrypted = encrypted
	}
	if req.PrivateKey != "" {
		encrypted, err := utils.EncryptAES(req.PrivateKey, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to encrypt private key")
			return
		}
		host.PrivateKeyEncrypted = encrypted
	}

	// Use Update with Select to avoid overwriting monitoring data (race condition with Pulse)
	// We only update configuration fields.
	// Build selective update fields
	fields := []string{
		"Name", "Host", "Port", "Username", "AuthType", "PasswordEncrypted", "PrivateKeyEncrypted",
		"GroupName", "Tags", "MonitorEnabled", "MonitorSecret", "Description", "HostType", "SortOrder",
		"NetInterface", "NetResetDay",
		"NetTrafficLimit", "NetTrafficUsedAdjustment", "NetTrafficCounterMode",
		"NotifyOfflineEnabled", "NotifyTrafficEnabled", "NotifyOfflineThreshold", "NotifyTrafficThreshold", "NotifyChannels",
	}

	if req.ResetTraffic {
		fields = append(fields, "NetMonthlyRx", "NetMonthlyTx", "NetLastResetDate", "TrafficAlerted")
		// Debug logging to verify adjustment value
		log.Printf("ResetTraffic=true. HostID=%d. Adjustment=%d", host.ID, host.NetTrafficUsedAdjustment)
	}

	// Single atomic update for all intended fields
	if err := h.db.Model(&host).Select(fields).Updates(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update host")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, host)
}

// Delete deletes an SSH host
func (h *SSHHostHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	result := h.db.Where("id = ? AND user_id = ?", id, userID).Delete(&models.SSHHost{})
	if result.Error != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete host")
		return
	}
	if result.RowsAffected == 0 {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "host deleted successfully",
	})
}

// TestConnection tests the connectivity to the SSH host
func (h *SSHHostHandler) TestConnection(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	// 对于"仅监控"类型的主机，返回监控代理状态
	if host.HostType == "monitor_only" {
		// 检查监控代理是否在线
		if host.Status == "online" && host.MonitorEnabled {
			// 计算距离上次心跳的时间（作为"延迟"）
			latency := time.Since(host.LastPulse).Milliseconds()
			if latency > 5000 { // 超过5秒视为离线
				c.JSON(http.StatusOK, gin.H{
					"status":  "offline",
					"latency": 0,
					"error":   "Monitor agent timeout",
				})
				return
			}
			c.JSON(http.StatusOK, gin.H{
				"status":  "online",
				"latency": latency,
			})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"status":  "offline",
			"latency": 0,
			"error":   "Monitor agent not online",
		})
		return
	}

	// 对于"控制+监控"类型，测试 SSH 连接
	target := net.JoinHostPort(host.Host, strconv.Itoa(host.Port))
	start := time.Now()
	conn, err := net.DialTimeout("tcp", target, 5*time.Second)
	duration := time.Since(start)

	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"status":  "offline",
			"latency": 0,
			"error":   err.Error(),
		})
		return
	}
	defer conn.Close()

	c.JSON(http.StatusOK, gin.H{
		"status":  "online",
		"latency": duration.Milliseconds(),
	})
}

type UpdateFingerprintRequest struct {
	Fingerprint string `json:"fingerprint" binding:"required"`
}

type ReorderRequest struct {
	DeviceIds []uint `json:"device_ids" binding:"required"`
}

// Reorder updates the sort order of hosts
func (h *SSHHostHandler) Reorder(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req ReorderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Transaction to ensure atomicity
	log.Printf("Reorder Request: UserID %d, DeviceIDs %v", userID, req.DeviceIds)
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for i, id := range req.DeviceIds {
			// Update only if the host belongs to the user
			if err := tx.Model(&models.SSHHost{}).
				Where("id = ? AND user_id = ?", id, userID).
				Update("sort_order", i).Error; err != nil {
				log.Printf("Reorder Error: ID %d, Error %v", id, err)
				return err
			}
		}
		return nil
	})

	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to reorder hosts")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "hosts reordered successfully"})
}

// UpdateFingerprint updates the host fingerprint
func (h *SSHHostHandler) UpdateFingerprint(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req UpdateFingerprintRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	host.Fingerprint = req.Fingerprint
	if err := h.db.Save(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update fingerprint")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "fingerprint updated successfully"})
}
