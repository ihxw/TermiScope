package handlers

import (
	"encoding/json"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/agenttransfer"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
)

const (
	agentTransferStartupTimeout  = 20 * time.Second
	agentTransferActivityTimeout = 20 * time.Second
)

func agentTransferReady(host models.SSHHost, now time.Time) bool {
	if !host.MonitorEnabled || host.Status != "online" || host.LastPulse.Before(now.Add(-30*time.Second)) {
		return false
	}
	if host.AgentTransferPort <= 0 || host.AgentTransferPort > 65535 {
		return false
	}
	_, ok := agenttransfer.NormalizeCertificateFingerprint(host.AgentTransferCertSHA256)
	return ok
}

func agentRelayReady(host models.SSHHost, now time.Time) bool {
	return host.MonitorEnabled && host.Status == "online" && host.AgentTransferRelay && !host.LastPulse.Before(now.Add(-30*time.Second))
}

func agentDirectPairReady(source, dest models.SSHHost, now time.Time) bool {
	return agentTransferReady(source, now) && (agentTransferReady(dest, now) || agentRelayReady(dest, now))
}

func agentTransferSourceURL(host models.SSHHost) string {
	address := strings.TrimSpace(host.Host)
	address = strings.TrimPrefix(address, "[")
	address = strings.TrimSuffix(address, "]")
	return "https://" + net.JoinHostPort(address, strconv.Itoa(host.AgentTransferPort)) + "/transfer"
}

// tryAgentTransfer asks the destination agent to pull a TLS-pinned stream from
// the source agent. Returns (attempted, success).
func (h *SftpHandler) tryAgentTransfer(
	c *gin.Context,
	srcHost, dstHost models.SSHHost,
	sourcePath, destPath string,
	isDir bool,
	totalSize int64,
) (bool, bool) {
	now := time.Now()
	if !agentDirectPairReady(srcHost, dstHost, now) || strings.TrimSpace(srcHost.Host) == "" {
		return false, false
	}

	transferID := utils.GenerateRandomString(32)
	token, err := agenttransfer.SignSourceToken(srcHost.MonitorSecret, agenttransfer.SourceClaims{
		Path: sourcePath, IsDir: isDir, ExpiresAt: now.Add(10 * time.Minute).Unix(), Nonce: transferID,
	})
	if err != nil {
		return false, false
	}
	payload, err := json.Marshal(agenttransfer.Command{
		Mode:       agenttransfer.ModeDirect,
		TransferID: transferID,
		SourceURL:  agentTransferSourceURL(srcHost), SourceToken: token,
		SourceCertSHA256: srcHost.AgentTransferCertSHA256,
		DestPath:         destPath, IsDir: isDir, TotalSize: totalSize,
	})
	if err != nil {
		return false, false
	}

	job := registerAgentTransferJob(transferID, srcHost.ID, dstHost.ID)
	registered := true
	defer func() {
		if registered {
			unregisterAgentTransferJob(transferID)
		}
	}()
	command := models.AgentCommand{HostID: dstHost.ID, Command: agenttransfer.CommandName, Payload: string(payload)}
	if err := h.db.Create(&command).Error; err != nil {
		return false, false
	}
	defer func() { _ = h.db.Delete(&models.AgentCommand{}, command.ID).Error }()

	sendTransferEvent(c, map[string]interface{}{
		"type": "info", "message": "using direct agent-to-agent HTTPS transfer",
	})
	timer := time.NewTimer(agentTransferStartupTimeout)
	defer timer.Stop()
	started := false
	lastTransferred := int64(0)
	resetTimer := func(timeout time.Duration) {
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		timer.Reset(timeout)
	}
	for {
		select {
		case <-c.Request.Context().Done():
			unregisterAgentTransferJob(transferID)
			registered = false
			return true, false
		case report := <-job.updates:
			switch report.Status {
			case "started":
				started = true
				resetTimer(agentTransferActivityTimeout)
			case "progress":
				started = true
				if report.Transferred > lastTransferred {
					lastTransferred = report.Transferred
					resetTimer(agentTransferActivityTimeout)
				}
				percent := 0
				if totalSize > 0 {
					percent = int(report.Transferred * 100 / totalSize)
					if percent > 99 {
						percent = 99
					}
				}
				sendTransferEvent(c, map[string]interface{}{
					"type": "progress", "percent": percent,
					"speed": formatSpeed(report.Speed), "transferred": report.Transferred, "total": totalSize,
				})
			case "complete":
				return true, true
			case "error":
				sendTransferEvent(c, map[string]interface{}{
					"type": "info", "message": "agent transfer failed, falling back: " + report.Message,
				})
				return true, false
			}
		case <-timer.C:
			unregisterAgentTransferJob(transferID)
			registered = false
			// The next progress report receives 410 and makes the destination agent
			// close and remove its partial file before another adapter starts.
			select {
			case <-c.Request.Context().Done():
				return true, false
			case <-time.After(2 * time.Second):
			}
			phase := "start"
			if started {
				phase = "continue"
			}
			sendTransferEvent(c, map[string]interface{}{
				"type": "info", "message": fmt.Sprintf("agent transfer did not %s in time, falling back", phase),
			})
			return true, false
		}
	}
}

// tryAgentRelay streams bounded chunks through the TermiScope server. Both
// agents only make outbound requests, so no host firewall port is required.
func (h *SftpHandler) tryAgentRelay(
	c *gin.Context,
	srcHost, dstHost models.SSHHost,
	sourcePath, destPath string,
	isDir bool,
	totalSize int64,
) (bool, bool) {
	now := time.Now()
	if !agentRelayReady(srcHost, now) || !agentRelayReady(dstHost, now) {
		return false, false
	}

	transferID := utils.GenerateRandomString(32)
	sourcePayload, err := json.Marshal(agenttransfer.Command{
		Mode: agenttransfer.ModeRelaySource, TransferID: transferID,
		SourcePath: sourcePath, IsDir: isDir, TotalSize: totalSize,
	})
	if err != nil {
		return false, false
	}
	destPayload, err := json.Marshal(agenttransfer.Command{
		Mode: agenttransfer.ModeRelayDest, TransferID: transferID,
		DestPath: destPath, IsDir: isDir, TotalSize: totalSize,
	})
	if err != nil {
		return false, false
	}

	reportJob := registerAgentTransferJob(transferID, srcHost.ID, dstHost.ID)
	relayJob := registerAgentRelayJob(transferID, srcHost.ID, dstHost.ID, isDir)
	registered := true
	cleanup := func() {
		if registered {
			unregisterAgentRelayJob(transferID)
			unregisterAgentTransferJob(transferID)
			registered = false
		}
	}
	defer cleanup()

	sourceCommand := models.AgentCommand{HostID: srcHost.ID, Command: agenttransfer.CommandName, Payload: string(sourcePayload)}
	if err := h.db.Create(&sourceCommand).Error; err != nil {
		return false, false
	}
	destCommand := models.AgentCommand{HostID: dstHost.ID, Command: agenttransfer.CommandName, Payload: string(destPayload)}
	if err := h.db.Create(&destCommand).Error; err != nil {
		_ = h.db.Delete(&models.AgentCommand{}, sourceCommand.ID).Error
		return false, false
	}
	defer func() {
		_ = h.db.Delete(&models.AgentCommand{}, []uint{sourceCommand.ID, destCommand.ID}).Error
	}()

	sendTransferEvent(c, map[string]interface{}{
		"type": "info", "message": "using outbound agent relay through TermiScope",
	})
	timer := time.NewTimer(agentTransferStartupTimeout)
	defer timer.Stop()
	started := false
	lastTransferred := int64(0)
	resetTimer := func(timeout time.Duration) {
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		timer.Reset(timeout)
	}
	cancelAndWait := func() {
		cleanup()
		select {
		case <-c.Request.Context().Done():
		case <-time.After(2 * time.Second):
		}
	}

	for {
		select {
		case <-c.Request.Context().Done():
			cleanup()
			return true, false
		case <-relayJob.activity:
			resetTimer(agentTransferActivityTimeout)
		case report := <-reportJob.updates:
			switch report.Status {
			case "started":
				started = true
				resetTimer(agentTransferActivityTimeout)
			case "progress":
				started = true
				if report.Transferred > lastTransferred {
					lastTransferred = report.Transferred
					resetTimer(agentTransferActivityTimeout)
				}
				percent := 0
				if totalSize > 0 {
					percent = int(report.Transferred * 100 / totalSize)
					if percent > 99 {
						percent = 99
					}
				}
				sendTransferEvent(c, map[string]interface{}{
					"type": "progress", "percent": percent,
					"speed": formatSpeed(report.Speed), "transferred": report.Transferred, "total": totalSize,
				})
			case "complete":
				return true, true
			case "error":
				sendTransferEvent(c, map[string]interface{}{
					"type": "info", "message": "agent relay failed, falling back: " + report.Message,
				})
				return true, false
			case "source_error":
				sendTransferEvent(c, map[string]interface{}{
					"type": "info", "message": "source agent relay failed, falling back: " + report.Message,
				})
				cancelAndWait()
				return true, false
			}
		case <-timer.C:
			cancelAndWait()
			phase := "start"
			if started {
				phase = "continue"
			}
			sendTransferEvent(c, map[string]interface{}{
				"type": "info", "message": fmt.Sprintf("agent relay did not %s in time, falling back", phase),
			})
			return true, false
		}
	}
}
