package handlers

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
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

	// DEBUG LOG
	// log.Printf("Agent %d requested tasks. Found: %d", host.ID, len(tasks))

	c.JSON(http.StatusOK, gin.H{"tasks": tasks})
}

// ReportNetworkResults saves the results from the agent
func (h *NetworkMonitorHandler) ReportNetworkResults(c *gin.Context) {
	// 1. Verify Agent
	// Although results contain TaskID, we should ensure the Agent matches the Task's Host?
	// Or just trust the Agent with the secret?
	// Trusting the agent is standard.
	_, err := h.verifyAgent(c)
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

	// 2. Save Results (Batch Insert)
	// Optionally set CreatedAt if missing
	now := time.Now()
	for i := range results {
		if results[i].CreatedAt.IsZero() {
			results[i].CreatedAt = now
		}
	}

	if err := h.DB.Create(&results).Error; err != nil {
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

	var host models.SSHHost
	if err := h.DB.Where("monitor_secret = ? AND monitor_enabled = ?", secret, true).First(&host).Error; err != nil {
		return nil, err
	}

	return &host, nil
}

// --- User Endpoints ---

// CreateTask adds a new monitoring task
func (h *NetworkMonitorHandler) CreateTask(c *gin.Context) {
	var task models.NetworkMonitorTask
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Host exists
	var host models.SSHHost
	if err := h.DB.First(&host, task.HostID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
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
	var task models.NetworkMonitorTask
	if err := h.DB.First(&task, id).Error; err != nil {
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
	if err := h.DB.Delete(&models.NetworkMonitorTask{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete task"})
		return
	}
	c.Status(http.StatusNoContent)
}

// GetHostTasks returns all tasks for a specific host (only template-created tasks)
func (h *NetworkMonitorHandler) GetHostTasks(c *gin.Context) {
	hostID := c.Param("id")

	// Query tasks with template information to get color
	var tasks []struct {
		models.NetworkMonitorTask
		Color string `json:"color"`
	}

	// Only return tasks created from templates (template_id > 0) and join with template to get color
	if err := h.DB.Table("network_monitor_tasks").
		Select("network_monitor_tasks.*, COALESCE(network_monitor_templates.color, '#1890ff') as color").
		Joins("LEFT JOIN network_monitor_templates ON network_monitor_tasks.template_id = network_monitor_templates.id").
		Where("network_monitor_tasks.host_id = ? AND network_monitor_tasks.template_id > 0", hostID).
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

	// Verify task exists
	var task models.NetworkMonitorTask
	if err := h.DB.First(&task, taskIDNum).Error; err != nil {
		utils.LogError("GetTaskStats: task not found: ID=%d | Error: %v | IP: %s", taskIDNum, err, c.ClientIP())
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	// Time Range (Default 24h)
	rangeStr := c.DefaultQuery("range", "24h")
	duration, err := time.ParseDuration(rangeStr)
	if err != nil {
		utils.LogError("GetTaskStats: invalid duration format: %s | Error: %v | Task ID: %d", rangeStr, err, taskIDNum)
		duration = 24 * time.Hour
	}

	since := time.Now().Add(-duration)

	var results []models.NetworkMonitorResult
	if err := h.DB.Where("task_id = ? AND created_at > ?", taskIDNum, since).Order("created_at asc").Find(&results).Error; err != nil {
		utils.LogError("GetTaskStats: database query failed | Task ID: %d | Since: %s | Error: %v | IP: %s",
			taskIDNum, since.Format(time.RFC3339), err, c.ClientIP())
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch stats"})
		return
	}

	// Log successful query for debugging
	log.Printf("GetTaskStats: returned %d results for task %d (range: %s) | IP: %s",
		len(results), taskIDNum, rangeStr, c.ClientIP())

	c.JSON(http.StatusOK, results)
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
	if err := h.DB.Delete(&models.NetworkMonitorTemplate{}, id).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete template"})
		return
	}
	c.Status(http.StatusNoContent)
}

type BatchApplyRequest struct {
	TemplateID uint   `json:"template_id"`
	HostIDs    []uint `json:"host_ids"`
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

	// Create tasks for each host
	// We use transaction to ensure atomicity
	tx := h.DB.Begin()
	for _, hostID := range req.HostIDs {
		// Check if task exists for this host with the same target and type
		var task models.NetworkMonitorTask
		result := tx.Where("host_id = ? AND type = ? AND target = ? AND port = ?",
			hostID, tmpl.Type, tmpl.Target, tmpl.Port).First(&task)

		if result.Error == nil {
			// Update existing task
			task.TemplateID = req.TemplateID
			task.Frequency = tmpl.Frequency
			task.Label = tmpl.Label
			if err := tx.Save(&task).Error; err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update task"})
				return
			}
		} else if result.Error == gorm.ErrRecordNotFound {
			// Create new task
			newTask := models.NetworkMonitorTask{
				HostID:     hostID,
				TemplateID: req.TemplateID, // Link to template
				Type:       tmpl.Type,
				Target:     tmpl.Target,
				Port:       tmpl.Port,
				Frequency:  tmpl.Frequency,
				Label:      tmpl.Label,
			}
			if err := tx.Create(&newTask).Error; err != nil {
				tx.Rollback()
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to apply to host"})
				return
			}
		} else {
			// Other DB error
			tx.Rollback()
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Database error checking task"})
			return
		}
	}
	tx.Commit()
	c.Status(http.StatusOK)
}

func (h *NetworkMonitorHandler) GetTemplateAssignments(c *gin.Context) {
	tmplID := c.Param("id")
	var tmpl models.NetworkMonitorTemplate
	if err := h.DB.First(&tmpl, tmplID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	// Find hosts that have a matching task
	var hostIDs []uint
	// We match by Target, Type, Port (and maybe Label?)
	// This is a heuristic since we don't link by ID.
	err := h.DB.Model(&models.NetworkMonitorTask{}).
		Where("target = ? AND type = ? AND port = ?", tmpl.Target, tmpl.Type, tmpl.Port).
		Pluck("host_id", &hostIDs).Error

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch assignments"})
		return
	}

	c.JSON(http.StatusOK, hostIDs)
}
