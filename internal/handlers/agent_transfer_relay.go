package handlers

import (
	"context"
	"encoding/hex"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/agenttransfer"
)

const relayBodyLimit = agenttransfer.RelayChunkSize + 1

type agentRelayChunk struct {
	data      []byte
	final     bool
	digest    string
	entryType string
	mode      string
}

type agentRelayJob struct {
	sourceHostID uint
	destHostID   uint
	isDir        bool
	ctx          context.Context
	cancel       context.CancelFunc
	chunks       chan agentRelayChunk
	activity     chan struct{}
	sourceMu     sync.Mutex
	destMu       sync.Mutex
	nextSource   uint64
	nextDest     uint64
	sourceDone   bool
	destDone     bool
}

var agentRelayJobs = struct {
	sync.RWMutex
	items map[string]*agentRelayJob
}{items: make(map[string]*agentRelayJob)}

func registerAgentRelayJob(id string, sourceHostID, destHostID uint, isDir bool) *agentRelayJob {
	ctx, cancel := context.WithCancel(context.Background())
	job := &agentRelayJob{
		sourceHostID: sourceHostID,
		destHostID:   destHostID,
		isDir:        isDir,
		ctx:          ctx,
		cancel:       cancel,
		chunks:       make(chan agentRelayChunk, 2),
		activity:     make(chan struct{}, 1),
	}
	agentRelayJobs.Lock()
	agentRelayJobs.items[id] = job
	agentRelayJobs.Unlock()
	return job
}

func lookupAgentRelayJob(id string) *agentRelayJob {
	agentRelayJobs.RLock()
	job := agentRelayJobs.items[id]
	agentRelayJobs.RUnlock()
	return job
}

func unregisterAgentRelayJob(id string) {
	agentRelayJobs.Lock()
	job := agentRelayJobs.items[id]
	delete(agentRelayJobs.items, id)
	agentRelayJobs.Unlock()
	if job != nil {
		job.cancel()
	}
}

func (j *agentRelayJob) signalActivity() {
	select {
	case j.activity <- struct{}{}:
	default:
	}
}

func parseRelaySequence(c *gin.Context) (uint64, bool) {
	sequence, err := strconv.ParseUint(c.Query("sequence"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid relay sequence"})
		return 0, false
	}
	return sequence, true
}

func validRelayMetadata(job *agentRelayJob, entryType, mode string) bool {
	wantType := "file"
	if job.isDir {
		wantType = "directory"
	}
	if entryType != wantType {
		return false
	}
	parsedMode, err := strconv.ParseUint(mode, 8, 32)
	return err == nil && parsedMode <= 0777
}

// UploadAgentRelayChunk accepts one bounded chunk from the source agent.
func (h *MonitorHandler) UploadAgentRelayChunk(c *gin.Context) {
	host, err := h.authenticateAgentRequest(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	job := lookupAgentRelayJob(c.Param("transferId"))
	if job == nil || job.sourceHostID != host.ID {
		c.JSON(http.StatusGone, gin.H{"error": "relay transfer is no longer active"})
		return
	}
	sequence, ok := parseRelaySequence(c)
	if !ok {
		return
	}
	entryType := c.GetHeader("X-Termiscope-Type")
	mode := c.GetHeader("X-Termiscope-Mode")
	if !validRelayMetadata(job, entryType, mode) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid relay metadata"})
		return
	}
	final := c.GetHeader("X-Termiscope-Relay-Final") == "1"
	digest := strings.ToLower(strings.TrimSpace(c.GetHeader("X-Termiscope-Relay-Digest")))
	if final {
		decoded, decodeErr := hex.DecodeString(digest)
		if decodeErr != nil || len(decoded) != 32 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid relay digest"})
			return
		}
	} else if digest != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "digest is only allowed on final chunk"})
		return
	}

	job.sourceMu.Lock()
	defer job.sourceMu.Unlock()
	if job.sourceDone || sequence != job.nextSource {
		c.JSON(http.StatusConflict, gin.H{"error": "unexpected relay sequence"})
		return
	}
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, relayBodyLimit)
	data, err := io.ReadAll(c.Request.Body)
	if err != nil || len(data) > agenttransfer.RelayChunkSize || (final && len(data) != 0) || (!final && len(data) == 0) {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "invalid relay chunk"})
		return
	}
	chunk := agentRelayChunk{data: data, final: final, digest: digest, entryType: entryType, mode: mode}
	select {
	case <-job.ctx.Done():
		c.JSON(http.StatusGone, gin.H{"error": "relay transfer is no longer active"})
		return
	case <-c.Request.Context().Done():
		return
	case job.chunks <- chunk:
		job.nextSource++
		job.sourceDone = final
		job.signalActivity()
		c.JSON(http.StatusOK, gin.H{"ok": true})
	}
}

// DownloadAgentRelayChunk returns the next chunk to the destination agent.
func (h *MonitorHandler) DownloadAgentRelayChunk(c *gin.Context) {
	host, err := h.authenticateAgentRequest(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}
	job := lookupAgentRelayJob(c.Param("transferId"))
	if job == nil || job.destHostID != host.ID {
		c.JSON(http.StatusGone, gin.H{"error": "relay transfer is no longer active"})
		return
	}
	sequence, ok := parseRelaySequence(c)
	if !ok {
		return
	}

	job.destMu.Lock()
	defer job.destMu.Unlock()
	if job.destDone || sequence != job.nextDest {
		c.JSON(http.StatusConflict, gin.H{"error": "unexpected relay sequence"})
		return
	}
	var chunk agentRelayChunk
	select {
	case <-job.ctx.Done():
		c.JSON(http.StatusGone, gin.H{"error": "relay transfer is no longer active"})
		return
	case <-c.Request.Context().Done():
		return
	case chunk = <-job.chunks:
	}
	job.nextDest++
	job.destDone = chunk.final
	job.signalActivity()
	c.Header("X-Termiscope-Type", chunk.entryType)
	c.Header("X-Termiscope-Mode", chunk.mode)
	if chunk.final {
		c.Header("X-Termiscope-Relay-Final", "1")
		c.Header("X-Termiscope-Relay-Digest", chunk.digest)
	}
	c.Data(http.StatusOK, "application/octet-stream", chunk.data)
}
