package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type NetworkMonitorHandler struct {
	DB *gorm.DB
}

func NewNetworkMonitorHandler(db *gorm.DB) *NetworkMonitorHandler {
	return &NetworkMonitorHandler{DB: db}
}

// --- Agent Endpoints ---

// GetNetworkTasks returns the tasks for the authenticated agent
func (h *NetworkMonitorHandler) GetNetworkTasks(c *gin.Context) {
	// 1. Verify Agent
	host, err := h.verifyAgent(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// 2. Fetch Tasks
	var tasks []models.NetworkMonitorTask
	if err := h.DB.Where("host_id = ?", host.ID).Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}

	etag := networkTasksETag(host.ID, tasks)
	c.Header("ETag", etag)
	if inm := c.GetHeader("If-None-Match"); inm != "" && inm == etag {
		c.Status(http.StatusNotModified)
		return
	}

	c.JSON(http.StatusOK, gin.H{"tasks": tasks})
}

// ReportNetworkResults saves the results from the agent
func (h *NetworkMonitorHandler) ReportNetworkResults(c *gin.Context) {
	// 1. Verify Agent
	// Although results contain TaskID, we should ensure the Agent matches the Task's Host?
	// Or just trust the Agent with the secret?
	// Trusting the agent is standard.
	host, err := h.verifyAgent(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var results []models.NetworkMonitorResult
	if err := c.ShouldBindJSON(&results); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(results) == 0 {
		c.Status(http.StatusOK)
		return
	}

	if len(results) > database.MaxNetworkMonitorResultsPerReport {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("too many results in one report (max %d)", database.MaxNetworkMonitorResultsPerReport),
		})
		return
	}

	var allowedTaskIDs []uint
	if err := h.DB.Model(&models.NetworkMonitorTask{}).Where("host_id = ?", host.ID).Pluck("id", &allowedTaskIDs).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate tasks"})
		return
	}
	allowed := make(map[uint]bool, len(allowedTaskIDs))
	for _, id := range allowedTaskIDs {
		allowed[id] = true
	}
	for _, r := range results {
		if !allowed[r.TaskID] {
			c.JSON(http.StatusForbidden, gin.H{"error": "task does not belong to this host"})
			return
		}
	}

	// 2. Save Results (Batch Insert)
	// Optionally set CreatedAt if missing
	now := time.Now()
	for i := range results {
		if results[i].CreatedAt.IsZero() {
			results[i].CreatedAt = now
		}
	}

	if err := h.DB.Create(&results).Error; err != nil {
		if migrateErr := database.EnsureNetworkMonitorTables(h.DB); migrateErr == nil {
			if err = h.DB.Create(&results).Error; err == nil {
				c.Status(http.StatusOK)
				return
			}
		}
		utils.LogError("ReportNetworkResults: save failed | count=%d | Error: %v", len(results), err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save results"})
		return
	}

	c.Status(http.StatusOK)
}

// verifyAgent checks the Authorization header
func (h *NetworkMonitorHandler) verifyAgent(c *gin.Context) (*models.SSHHost, error) {
	authHeader := c.GetHeader("Authorization")
	if len(authHeader) < 7 || authHeader[:7] != "Bearer " {
		return nil, http.ErrNoCookie // Just a generic error
	}
	secret := authHeader[7:]

	// We need the Host ID to verify.
	// The Agent typically sends it in the body for Pulse, but GET requests don't have body.
	// So we should expect it in a Header "X-Host-ID" or query param?
	// Or we just search by Secret? Secrets are unique per host.
	// Let's search by Secret.

	host, err := lookupAgentHostBySecret(h.DB, secret)
	if err != nil {
		return nil, err
	}
	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		return nil, fmt.Errorf("invalid secret")
	}
	return host, nil
}

// --- User Endpoints ---

// CreateTask adds a new monitoring task
func (h *NetworkMonitorHandler) CreateTask(c *gin.Context) {
	var task models.NetworkMonitorTask
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if _, ok := loadSSHHostForUserUint(h.DB, task.HostID, c); !ok {
		denyHostAccess(c)
		return
	}

	// Set Defaults
	if task.Frequency <= 0 {
		task.Frequency = 60
	}

	if err := h.DB.Create(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create task"})
		return
	}

	c.JSON(http.StatusCreated, task)
}

// UpdateTask modifies an existing task
func (h *NetworkMonitorHandler) UpdateTask(c *gin.Context) {
	id := c.Param("id")
	task, ok := loadNetworkTaskForUser(h.DB, id, c)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	var req models.NetworkMonitorTask
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Allowed updates
	task.Target = req.Target
	task.Type = req.Type
	task.Port = req.Port
	task.Label = req.Label
	if req.Frequency > 0 {
		task.Frequency = req.Frequency
	}

	if err := h.DB.Save(&task).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update task"})
		return
	}

	c.JSON(http.StatusOK, task)
}

// DeleteTask removes a task
func (h *NetworkMonitorHandler) DeleteTask(c *gin.Context) {
	id := c.Param("id")
	if _, ok := loadNetworkTaskForUser(h.DB, id, c); !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	if err := h.DB.Delete(&models.NetworkMonitorTask{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete task"})
		return
	}
	c.Status(http.StatusNoContent)
}

// GetHostTasks returns all tasks for a specific host (only template-created tasks)
func (h *NetworkMonitorHandler) GetHostTasks(c *gin.Context) {
	hostID := c.Param("id")
	if _, ok := loadSSHHostForUser(h.DB, hostID, c); !ok {
		denyHostAccess(c)
		return
	}

	// Query tasks with template information to get color
	var tasks []struct {
		models.NetworkMonitorTask
		Color string `json:"color"`
	}

	// All tasks for host (manual + template); color from template when linked
	if err := h.DB.Table("network_monitor_tasks").
		Select("network_monitor_tasks.*, COALESCE(network_monitor_templates.color, '#1890ff') as color").
		Joins("LEFT JOIN network_monitor_templates ON network_monitor_tasks.template_id = network_monitor_templates.id").
		Where("network_monitor_tasks.host_id = ?", hostID).
		Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"tasks": tasks})
}

// GetTaskStats returns historical data for a task (for charts)
func (h *NetworkMonitorHandler) GetTaskStats(c *gin.Context) {
	taskID := c.Param("taskId")

	// Validate taskID is a number
	var taskIDNum uint
	if _, err := fmt.Sscanf(taskID, "%d", &taskIDNum); err != nil {
		utils.LogError("GetTaskStats: invalid task ID format: %s | Error: %v | IP: %s", taskID, err, c.ClientIP())
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid task ID"})
		return
	}

	task, ok := loadNetworkTaskForUser(h.DB, taskID, c)
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}
	_ = task

	// Time Range (Default 24h); supports 1h, 24h, 1d, 7d, etc.
	rangeStr := c.DefaultQuery("range", "24h")
	duration, err := database.ParseNetworkStatsRange(rangeStr)
	if err != nil {
		utils.LogError("GetTaskStats: invalid duration format: %s | Error: %v | Task ID: %d", rangeStr, err, taskIDNum)
		duration = 24 * time.Hour
	}

	since := time.Now().Add(-duration)

	results, err := database.QueryNetworkMonitorResults(h.DB, taskIDNum, since)
	if err != nil {
		utils.LogError("GetTaskStats: database query failed | Task ID: %d | Since: %s | Error: %v | IP: %s",
			taskIDNum, since.Format(time.RFC3339), err, c.ClientIP())
		if database.IsDatabaseCorrupted(err) {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "Database is corrupted",
				"details": "SQLite reports disk image is malformed. Stop the server, back up data/termiscope.db, then run: sqlite3 data/termiscope.db \".recover\" | sqlite3 data/termiscope_recovered.db",
			})
			return
		}
		resp := gin.H{"error": "Failed to fetch stats"}
		if gin.Mode() == gin.DebugMode {
			resp["details"] = err.Error()
		}
		c.JSON(http.StatusInternalServerError, resp)
		return
	}

	if gin.Mode() == gin.DebugMode {
		log.Printf("GetTaskStats: returned %d results for task %d (range: %s)",
			len(results), taskIDNum, rangeStr)
	}

	c.JSON(http.StatusOK, results)
}

// GetHostLatencyStats returns chart data for all tasks on a host in one request.
func (h *NetworkMonitorHandler) GetHostLatencyStats(c *gin.Context) {
	hostID := c.Param("id")
	if _, ok := loadSSHHostForUser(h.DB, hostID, c); !ok {
		denyHostAccess(c)
		return
	}

	rangeStr := c.DefaultQuery("range", "24h")
	duration, err := database.ParseNetworkStatsRange(rangeStr)
	if err != nil {
		duration = 24 * time.Hour
	}
	since := time.Now().Add(-duration)

	var tasks []struct {
		models.NetworkMonitorTask
		Color string `json:"color"`
	}
	if err := h.DB.Table("network_monitor_tasks").
		Select("network_monitor_tasks.*, COALESCE(network_monitor_templates.color, '#1890ff') as color").
		Joins("LEFT JOIN network_monitor_templates ON network_monitor_tasks.template_id = network_monitor_templates.id").
		Where("network_monitor_tasks.host_id = ?", hostID).
		Find(&tasks).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch tasks"})
		return
	}

	type TaskSeries struct {
		TaskID uint                          `json:"task_id"`
		Label  string                        `json:"label"`
		Color  string                        `json:"color"`
		Data   []models.NetworkMonitorResult `json:"data"`
	}
	series := make([]TaskSeries, 0, len(tasks))
	for _, t := range tasks {
		data, qErr := database.QueryNetworkMonitorResults(h.DB, t.ID, since)
		if qErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch stats"})
			return
		}
		series = append(series, TaskSeries{
			TaskID: t.ID,
			Label:  t.Label,
			Color:  t.Color,
			Data:   data,
		})
	}

	c.JSON(http.StatusOK, gin.H{"tasks": tasks, "series": series})
}

// --- Template Endpoints ---
func (h *NetworkMonitorHandler) CreateTemplate(c *gin.Context) {
	var tmpl models.NetworkMonitorTemplate
	if err := c.ShouldBindJSON(&tmpl); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if tmpl.Frequency <= 0 {
		tmpl.Frequency = 60
	}
	if tmpl.Color == "" {
		tmpl.Color = "#1890ff" // Set default color if not provided
	}
	if err := h.DB.Create(&tmpl).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create template"})
		return
	}
	c.JSON(http.StatusCreated, tmpl)
}

func (h *NetworkMonitorHandler) UpdateTemplate(c *gin.Context) {
	id := c.Param("id")
	var req models.NetworkMonitorTemplate
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var tmpl models.NetworkMonitorTemplate
	if err := h.DB.First(&tmpl, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	// Update fields
	tmpl.Name = req.Name
	tmpl.Type = req.Type
	tmpl.Target = req.Target
	tmpl.Port = req.Port
	tmpl.Frequency = req.Frequency
	tmpl.Label = req.Label
	tmpl.Color = req.Color // Update color field

	if err := h.DB.Save(&tmpl).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update template"})
		return
	}
	c.JSON(http.StatusOK, tmpl)
}

func (h *NetworkMonitorHandler) GetTemplates(c *gin.Context) {
	var tmpls []models.NetworkMonitorTemplate
	if err := h.DB.Find(&tmpls).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch templates"})
		return
	}
	c.JSON(http.StatusOK, tmpls)
}

func (h *NetworkMonitorHandler) DeleteTemplate(c *gin.Context) {
	id := c.Param("id")

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete template"})
		return
	}

	if err := tx.Model(&models.NetworkMonitorTask{}).Where("template_id = ?", id).Update("template_id", 0).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to unlink template tasks"})
		return
	}
	if err := tx.Delete(&models.NetworkMonitorTemplate{}, id).Error; err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete template"})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete template"})
		return
	}
	c.Status(http.StatusNoContent)
}

type BatchApplyRequest struct {
	TemplateID uint   `json:"template_id"`
	HostIDs    []uint `json:"host_ids"`
}

func uniqueUintIDs(ids []uint) []uint {
	seen := make(map[uint]struct{}, len(ids))
	out := make([]uint, 0, len(ids))
	for _, id := range ids {
		if id == 0 {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func getTemplateAssignedHostIDs(db *gorm.DB, templateID, userID uint) ([]uint, error) {
	hostQuery := db.Model(&models.SSHHost{}).
		Select("id").
		Where("user_id = ? AND deleted_at IS NULL", userID)

	var hostIDs []uint
	err := db.Model(&models.NetworkMonitorTask{}).
		Where("template_id = ? AND host_id IN (?)", templateID, hostQuery).
		Pluck("host_id", &hostIDs).Error
	if err != nil {
		return nil, err
	}
	return uniqueUintIDs(hostIDs), nil
}

func syncTemplateAssignments(tx *gorm.DB, tmpl models.NetworkMonitorTemplate, userID uint, selectedHostIDs []uint) error {
	selectedHostIDs = uniqueUintIDs(selectedHostIDs)
	activeHostQuery := tx.Model(&models.SSHHost{}).
		Select("id").
		Where("user_id = ? AND deleted_at IS NULL", userID)

	unlink := tx.Model(&models.NetworkMonitorTask{}).
		Where("template_id = ? AND host_id IN (?)", tmpl.ID, activeHostQuery)
	if len(selectedHostIDs) > 0 {
		unlink = unlink.Where("host_id NOT IN ?", selectedHostIDs)
	}
	if err := unlink.Update("template_id", 0).Error; err != nil {
		return err
	}

	for _, hostID := range selectedHostIDs {
		// Check if task exists for this host with the same target and type
		var task models.NetworkMonitorTask
		result := tx.Where("host_id = ? AND type = ? AND target = ? AND port = ?",
			hostID, tmpl.Type, tmpl.Target, tmpl.Port).First(&task)

		if result.Error == nil {
			// Update existing task
			task.TemplateID = tmpl.ID
			task.Frequency = tmpl.Frequency
			task.Label = tmpl.Label
			if err := tx.Save(&task).Error; err != nil {
				return err
			}
		} else if result.Error == gorm.ErrRecordNotFound {
			// Create new task
			newTask := models.NetworkMonitorTask{
				HostID:     hostID,
				TemplateID: tmpl.ID,
				Type:       tmpl.Type,
				Target:     tmpl.Target,
				Port:       tmpl.Port,
				Frequency:  tmpl.Frequency,
				Label:      tmpl.Label,
			}
			if err := tx.Create(&newTask).Error; err != nil {
				return err
			}
		} else {
			return result.Error
		}
	}

	return nil
}

func (h *NetworkMonitorHandler) BatchApplyTemplate(c *gin.Context) {
	var req BatchApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var tmpl models.NetworkMonitorTemplate
	if err := h.DB.First(&tmpl, req.TemplateID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	userID := middleware.GetUserID(c)
	req.HostIDs = uniqueUintIDs(req.HostIDs)
	var allowedIDs []uint
	if len(req.HostIDs) > 0 {
		if err := h.DB.Model(&models.SSHHost{}).Where("user_id = ? AND id IN ?", userID, req.HostIDs).Pluck("id", &allowedIDs).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to verify hosts"})
			return
		}
		if len(allowedIDs) != len(req.HostIDs) {
			c.JSON(http.StatusForbidden, gin.H{"error": "Host not found or access denied"})
			return
		}
	}

	tx := h.DB.Begin()
	if tx.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to apply template"})
		return
	}
	if err := syncTemplateAssignments(tx, tmpl, userID, req.HostIDs); err != nil {
		tx.Rollback()
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to apply template"})
		return
	}
	if err := tx.Commit().Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to apply template"})
		return
	}
	c.Status(http.StatusOK)
}

func (h *NetworkMonitorHandler) GetTemplateAssignments(c *gin.Context) {
	tmplID := c.Param("id")
	var tmpl models.NetworkMonitorTemplate
	if err := h.DB.First(&tmpl, tmplID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	hostIDs, err := getTemplateAssignedHostIDs(h.DB, tmpl.ID, middleware.GetUserID(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch assignments"})
		return
	}

	c.JSON(http.StatusOK, hostIDs)
}
