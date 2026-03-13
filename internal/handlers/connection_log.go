package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type ConnectionLogHandler struct {
	db *gorm.DB
}

func NewConnectionLogHandler(db *gorm.DB) *ConnectionLogHandler {
	return &ConnectionLogHandler{db: db}
}

// List returns connection logs
func (h *ConnectionLogHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	startDate := c.Query("start_date")
	endDate := c.Query("end_date")
	hostID := c.Query("host_id")
	queryUserID := c.Query("user_id")

	query := h.db.Model(&models.ConnectionLog{}).Preload("User").Preload("SSHHost")

	// Non-admin users can only see their own logs
	if role != "admin" {
		query = query.Where("user_id = ?", userID)
	} else if queryUserID != "" {
		// Admin can filter by user
		query = query.Where("user_id = ?", queryUserID)
	}

	// Date range filter
	if startDate != "" {
		if t, err := time.Parse("2006-01-02", startDate); err == nil {
			query = query.Where("connected_at >= ?", t)
		}
	}
	if endDate != "" {
		if t, err := time.Parse("2006-01-02", endDate); err == nil {
			query = query.Where("connected_at <= ?", t.Add(24*time.Hour))
		}
	}

	// Host filter
	if hostID != "" {
		query = query.Where("ssh_host_id = ?", hostID)
	}

	// Count total
	var total int64
	query.Count(&total)

	// Paginate
	var logs []models.ConnectionLog
	offset := (page - 1) * pageSize
	if err := query.Order("connected_at DESC").Offset(offset).Limit(pageSize).Find(&logs).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch logs")
		return
	}

	utils.PaginatedResponse(c, http.StatusOK, logs, total, page, pageSize)
}
