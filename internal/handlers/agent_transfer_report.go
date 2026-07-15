package handlers

import (
	"net/http"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/agenttransfer"
)

type agentTransferJob struct {
	sourceHostID uint
	destHostID   uint
	updates      chan agenttransfer.Report
}

var agentTransferJobs = struct {
	sync.RWMutex
	items map[string]*agentTransferJob
}{items: make(map[string]*agentTransferJob)}

func registerAgentTransferJob(id string, sourceHostID, destHostID uint) *agentTransferJob {
	job := &agentTransferJob{sourceHostID: sourceHostID, destHostID: destHostID, updates: make(chan agenttransfer.Report, 64)}
	agentTransferJobs.Lock()
	agentTransferJobs.items[id] = job
	agentTransferJobs.Unlock()
	return job
}

func unregisterAgentTransferJob(id string) {
	agentTransferJobs.Lock()
	delete(agentTransferJobs.items, id)
	agentTransferJobs.Unlock()
}

func publishAgentTransferReport(hostID uint, report agenttransfer.Report) bool {
	agentTransferJobs.RLock()
	job := agentTransferJobs.items[report.TransferID]
	agentTransferJobs.RUnlock()
	if job == nil {
		return false
	}
	if report.Status == "source_error" {
		if job.sourceHostID != hostID {
			return false
		}
	} else if job.destHostID != hostID {
		return false
	}
	select {
	case job.updates <- report:
		return true
	default:
		return report.Status == "progress"
	}
}

// ReportAgentTransfer receives progress from the destination agent. A missing
// job tells the agent to stop and remove its partial output.
func (h *MonitorHandler) ReportAgentTransfer(c *gin.Context) {
	host, err := h.authenticateAgentRequest(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 64*1024)
	var report agenttransfer.Report
	if err := c.ShouldBindJSON(&report); err != nil || report.TransferID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid transfer report"})
		return
	}
	switch report.Status {
	case "started", "progress", "complete", "error", "source_error":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid transfer status"})
		return
	}
	if len(report.TransferID) > 128 || report.Transferred < 0 || report.Total < 0 || report.Speed < 0 || len(report.Message) > 2048 || strings.ContainsAny(report.TransferID, " \t\r\n") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid transfer report values"})
		return
	}
	if !publishAgentTransferReport(host.ID, report) {
		c.JSON(http.StatusGone, gin.H{"error": "transfer is no longer active"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
