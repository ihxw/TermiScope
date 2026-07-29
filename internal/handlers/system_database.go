package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/utils"
)

// GetDatabaseStats returns network monitor table statistics.
func (h *SystemHandler) GetDatabaseStats(c *gin.Context) {
	count, err := database.CountNetworkMonitorResults(h.db)
	if err != nil {
		if database.IsDatabaseCorrupted(err) {
			utils.ErrorResponse(c, http.StatusInternalServerError, "database corruption detected; run scripts/repair_database.sh")
			return
		}
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to count monitor results: "+err.Error())
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"network_monitor_results_count": count,
		"alert_threshold":             database.NetworkMonitorAlertThreshold,
		"retention_hours":             24,
		"over_threshold":              count >= database.NetworkMonitorAlertThreshold,
	})
}

// PruneNetworkMonitorData deletes network monitor results older than 24 hours.
func (h *SystemHandler) PruneNetworkMonitorData(c *gin.Context) {
	before, _ := database.CountNetworkMonitorResults(h.db)

	deleted, err := database.PruneNetworkMonitorResults(h.db, 0) // 0 uses default 24h in PruneNetworkMonitorResults
	if err != nil {
		if database.IsDatabaseCorrupted(err) {
			utils.ErrorResponse(c, http.StatusInternalServerError, "database corruption detected; run scripts/repair_database.sh")
			return
		}
		utils.ErrorResponse(c, http.StatusInternalServerError, "prune failed: "+err.Error())
		return
	}

	vacuumRan := false
	if deleted >= 10000 {
		if err := h.db.Exec("VACUUM").Error; err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "prune succeeded but VACUUM failed: "+err.Error())
			return
		}
		vacuumRan = true
	}

	remaining, _ := database.CountNetworkMonitorResults(h.db)

	// Notify if still over threshold after manual prune
	database.CheckAndNotifyNetworkMonitorOverflow(h.db, h.config.Security.EncryptionKey)

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"deleted":           deleted,
		"count_before":      before,
		"remaining":         remaining,
		"vacuum_ran":        vacuumRan,
		"over_threshold":    remaining >= database.NetworkMonitorAlertThreshold,
		"alert_threshold":   database.NetworkMonitorAlertThreshold,
	})
}
