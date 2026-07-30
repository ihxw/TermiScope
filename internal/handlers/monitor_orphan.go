package handlers

import (
	_ "embed"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/utils"
)

//go:embed orphan_agent_cleanup.sh
var embeddedOrphanCleanupScript string

// ListOrphanAgents returns agents still reporting for deleted or unknown host IDs.
// We re-check the DB at list time so entries that became valid again (e.g. a host that was
// briefly missing during a DB hiccup or a soft-deleted host that was restored) self-heal
// instead of haunting the orphan page forever.
func (h *MonitorHandler) ListOrphanAgents(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"agents": listOrphanAgentsFiltered(h.DB),
	})
}

// GetOrphanCleanupScript returns a bash script to remove an orphan agent (no monitor secret required).
func (h *MonitorHandler) GetOrphanCleanupScript(c *gin.Context) {
	hostID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || hostID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}

	script, err := loadOrphanCleanupScript(uint(hostID))
	if err != nil {
		log.Printf("orphan cleanup script: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load cleanup script"})
		return
	}

	c.Header("Content-Type", "text/plain; charset=utf-8")
	c.String(http.StatusOK, script)
}

// DismissOrphanAgent removes an entry from the orphan registry (does not stop remote agents).
func (h *MonitorHandler) DismissOrphanAgent(c *gin.Context) {
	hostID, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || hostID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid host id"})
		return
	}
	dismissOrphanAgent(uint(hostID))
	utils.SuccessResponse(c, http.StatusOK, gin.H{"dismissed": true})
}

func loadOrphanCleanupScript(hostID uint) (string, error) {
	var tmpl string
	if path, err := utils.ResolveScriptsFile("orphan_agent_cleanup.sh"); err == nil {
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return "", readErr
		}
		tmpl = string(data)
	} else {
		tmpl = embeddedOrphanCleanupScript
		if tmpl == "" {
			return "", err
		}
	}
	script := strings.ReplaceAll(tmpl, "{{HOST_ID}}", strconv.FormatUint(uint64(hostID), 10))
	return strings.ReplaceAll(script, "\r\n", "\n"), nil
}
