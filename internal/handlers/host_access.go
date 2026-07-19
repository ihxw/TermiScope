package handlers

import (
	"fmt"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// loadSSHHostForUser returns a host if the caller may access it (owner or admin).
func loadSSHHostForUser(db *gorm.DB, hostID string, c *gin.Context) (*models.SSHHost, bool) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)

	var host models.SSHHost
	q := db.Where("id = ?", hostID)
	if role != "admin" {
		q = q.Where("user_id = ?", userID)
	}
	if err := q.First(&host).Error; err != nil {
		return nil, false
	}
	return &host, true
}

// loadSSHHostForUserUint is the uint host ID variant.
func loadSSHHostForUserUint(db *gorm.DB, hostID uint, c *gin.Context) (*models.SSHHost, bool) {
	return loadSSHHostForUser(db, strconv.FormatUint(uint64(hostID), 10), c)
}

// denyHostAccess writes 404 (avoid leaking existence) when access is denied.
func denyHostAccess(c *gin.Context) {
	c.JSON(http.StatusNotFound, gin.H{"error": "Host not found"})
}

// monitorAllowedHostIDs returns nil for admin (all hosts), or a set of owned host IDs.
func monitorAllowedHostIDs(db *gorm.DB, userID uint, role string) (map[uint]bool, bool) {
	if role == "admin" {
		return nil, true
	}
	var ids []uint
	if err := db.Model(&models.SSHHost{}).Where("user_id = ?", userID).Pluck("id", &ids).Error; err != nil {
		return map[uint]bool{}, false
	}
	set := make(map[uint]bool, len(ids))
	for _, id := range ids {
		set[id] = true
	}
	return set, false
}

// loadNetworkTaskForUser ensures the task's host belongs to the caller.
func loadNetworkTaskForUser(db *gorm.DB, taskID string, c *gin.Context) (*models.NetworkMonitorTask, bool) {
	var task models.NetworkMonitorTask
	if err := db.First(&task, taskID).Error; err != nil {
		return nil, false
	}
	if _, ok := loadSSHHostForUserUint(db, task.HostID, c); !ok {
		return nil, false
	}
	return &task, true
}

// verifyMonitorSecret checks host_id + secret. Used by public agent/install routes.
func verifyMonitorSecret(db *gorm.DB, hostID, secret string) (*models.SSHHost, error) {
	if hostID == "" || secret == "" {
		return nil, fmt.Errorf("host_id and secret required")
	}
	var host models.SSHHost
	if err := db.First(&host, hostID).Error; err != nil {
		return nil, fmt.Errorf("host not found")
	}
	if !utils.MonitorSecretEqual(host.MonitorSecret, secret) {
		return nil, fmt.Errorf("invalid secret")
	}
	return &host, nil
}

// extractMonitorSecret reads monitor secret from the Authorization Bearer header.
func extractMonitorSecret(c *gin.Context) string {
	if auth := c.GetHeader("Authorization"); len(auth) >= 7 && auth[:7] == "Bearer " {
		return auth[7:]
	}
	return ""
}
