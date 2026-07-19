package handlers

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime/debug"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

// createUpgrader creates a WebSocket upgrader with origin validation
func createUpgrader(allowedOrigins []string, debugMode bool) websocket.Upgrader {
	return websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			return middleware.IsOriginAllowed(
				r.Header.Get("Origin"),
				r.Header.Get("Host"),
				allowedOrigins,
				debugMode,
			)
		},
		EnableCompression: true,
	}
}

type SSHWebSocketHandler struct {
	db     *gorm.DB
	config *config.Config
}

func NewSSHWebSocketHandler(db *gorm.DB, cfg *config.Config) *SSHWebSocketHandler {
	return &SSHWebSocketHandler{
		db:     db,
		config: cfg,
	}
}

// saveDB safely saves a record to DB, logging errors without failing the operation
func (h *SSHWebSocketHandler) saveDB(value interface{}) {
	if err := h.db.Save(value).Error; err != nil {
		utils.LogError("DB save failed: %v", err)
	}
}

// createDB safely creates a record, logging errors without failing the operation
func (h *SSHWebSocketHandler) createDB(value interface{}) {
	if err := h.db.Create(value).Error; err != nil {
		utils.LogError("DB create failed: %v", err)
	}
}

type WSMessage struct {
	Type string      `json:"type"` // input, resize
	Data interface{} `json:"data"`
}

type ResizeData struct {
	Rows int `json:"rows"`
	Cols int `json:"cols"`
}

const wsCloseCodeIdleTimeout = 4000

func isTimeoutError(err error) bool {
	if err == nil {
		return false
	}
	var netErr net.Error
	return errors.As(err, &netErr) && netErr.Timeout() || os.IsTimeout(err)
}

// HandleWebSocket handles WebSocket connections for SSH
func (h *SSHWebSocketHandler) HandleWebSocket(c *gin.Context) {
	ticketID := c.Query("ticket")
	ticket, ok := utils.ValidateTicket(ticketID)
	if !ok {
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid or expired ticket")
		return
	}

	userID := ticket.UserID
	hostID := c.Param("hostId")

	// Get SSH host from database
	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", hostID, userID).First(&host).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return
	}

	// 检查是否有更新指纹的请求
	if c.Query("update_fingerprint") == "true" {
		// 用户确认更新，保存新指纹
		newFp := c.Query("fingerprint")
		if newFp != "" {
			// Security: validate fingerprint format to prevent arbitrary string injection.
			// Accepts SHA256:base64... or MD5 colon-separated hex format.
			validFp := regexp.MustCompile(`^(SHA256:[A-Za-z0-9+/=]{43,44}|([0-9a-fA-F]{2}:){15}[0-9a-fA-F]{2})$`)
			if !validFp.MatchString(newFp) {
				utils.ErrorResponse(c, http.StatusBadRequest, "invalid fingerprint format")
				return
			}
			host.Fingerprint = newFp
			if err := h.db.Save(&host).Error; err != nil {
				utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update fingerprint")
				return
			}

			// 记录安全事件
			models.SecurityEventLog(h.db, models.ConfigChanged, models.SeverityLow,
				userID, ticket.Username, c.ClientIP(), c.Request.UserAgent(),
				fmt.Sprintf("Updated SSH host fingerprint for %s", host.Name),
				map[string]interface{}{
					"host_id":   host.ID,
					"host_name": host.Name,
					"new_fp":    newFp,
					"old_fp":    host.Fingerprint,
				})

			log.Printf("✅ Updated fingerprint for host %s (%s): %s", host.Name, host.Host, newFp)
		}
		// 继续执行，重新尝试连接
	}

	// Decrypt credentials
	password, privateKey := decryptHostCredentials(&host, h.config.Security.EncryptionKey)
	if password == "" && privateKey == "" {
		utils.ErrorResponse(c, http.StatusInternalServerError, "host has no credentials configured")
		return
	}

	// Create upgrader with origin validation
	upgrader := createUpgrader(h.config.Server.AllowedOrigins, h.config.Server.Mode == "debug")

	// Upgrade to WebSocket
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade to WebSocket: %v", err)
		return
	}
	defer ws.Close()

	// Parse idle timeout
	idleTimeout, err := time.ParseDuration(h.config.SSH.IdleTimeout)
	if err != nil {
		idleTimeout = 30 * time.Minute
	}

	// wsMutex ensures concurrent writes to the websocket are safe
	var wsMutex sync.Mutex

	// Helper to write to websocket safely
	writeParams := func(msgType int, data []byte) error {
		wsMutex.Lock()
		defer wsMutex.Unlock()
		return ws.WriteMessage(msgType, data)
	}

	writeJSON := func(v interface{}) error {
		wsMutex.Lock()
		defer wsMutex.Unlock()
		return ws.WriteJSON(v)
	}

	// Create connection log
	connLog := &models.ConnectionLog{
		UserID:      userID,
		SSHHostID:   &host.ID,
		Host:        host.Host,
		Port:        host.Port,
		Username:    host.Username,
		Status:      "connecting",
		ConnectedAt: time.Now(),
	}
	h.createDB(connLog)

	connector := newHostConnector(h.config.Security.EncryptionKey, h.config.SSH.Timeout, func(host *models.SSHHost) error {
		return h.db.Save(host).Error
	})
	sshClient, observedFingerprint, err := connector.open(&host, false)
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)

		// Check for host key mismatch
		errMsg := err.Error()
		if strings.Contains(errMsg, "host key fingerprint mismatch") {
			// 返回错误和确认选项给前端
			writeJSON(gin.H{
				"type": "error",
				"code": "fingerprint_mismatch",
				"data": fmt.Sprintf("远程主机身份标识已更改！这可能是 VPS 重装系统或中间人攻击。\n新指纹：%s", observedFingerprint),
				"meta": gin.H{
					"new_fingerprint": observedFingerprint,
					"host_id":         host.ID,
					"action":          "confirm_update", // 提示用户可以确认更新
				},
			})
		} else {
			writeJSON(gin.H{"type": "error", "data": "SSH 连接失败：" + err.Error()})
		}
		return
	}
	defer sshClient.Close()

	// Create session
	if err := sshClient.NewSession(); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to create session: " + err.Error()})
		return
	}

	session := sshClient.GetSession()

	// Set environment variables for true color support
	// Try Setenv first (may fail if sshd doesn't allow it via AcceptEnv, silently ignore)
	session.Setenv("COLORTERM", "truecolor")

	// Request PTY
	if err := sshClient.RequestPTY("xterm-256color", 24, 80); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to request PTY: " + err.Error()})
		return
	}

	// Set up pipes
	stdin, err := session.StdinPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stdin pipe: " + err.Error()})
		return
	}

	stdout, err := session.StdoutPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stdout pipe: " + err.Error()})
		return
	}

	stderr, err := session.StderrPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stderr pipe: " + err.Error()})
		return
	}

	// Start interactive shell (PowerShell/CMD on Windows, bash, or server default)
	remoteShell := host.RemoteShell
	if remoteShell == "" {
		remoteShell = "default"
	}
	if err := sshClient.StartInteractive(remoteShell, host.OsType); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.saveDB(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to start shell: " + err.Error()})
		return
	}

	// Update connection log
	connLog.Status = "success"
	h.saveDB(connLog)

	// Send success message
	writeJSON(gin.H{"type": "connected", "data": "Connected successfully"})

	// Channel to signal completion
	done := make(chan struct{})
	var once sync.Once
	closeCode := websocket.CloseNormalClosure
	closeReason := "session closed"
	closeDoneWithReason := func(code int, reason string) {
		once.Do(func() {
			closeCode = code
			closeReason = reason
			close(done)
		})
	}
	closeDone := func() {
		closeDoneWithReason(websocket.CloseNormalClosure, "session closed")
	}

	// Handle recording
	record := c.Query("record") == "true"
	var recording *models.TerminalRecording
	var recordBuf *bufio.Writer
	if record {
		recordingDir := "data/recordings"
		os.MkdirAll(recordingDir, 0700)

		fileName := fmt.Sprintf("%d-%d-%d.cast", userID, host.ID, time.Now().Unix())
		filePath := filepath.Join(recordingDir, fileName)

		f, err := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
		if err == nil {
			recordBuf = bufio.NewWriter(f)
			defer f.Close()
			recording = &models.TerminalRecording{
				UserID:    userID,
				SSHHostID: host.ID,
				Host:      host.Host,
				Username:  host.Username,
				FilePath:  filePath,
				StartTime: time.Now(),
			}
			h.createDB(recording)
		}
	}

	// Ping loop to keep connection alive
	go func() {
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Ping Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
			}
		}()
		ticker := time.NewTicker(20 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if err := writeParams(websocket.PingMessage, []byte{}); err != nil {
					return
				}
				// Send SSH keepalive to prevent timeout
				if sshClient != nil {
					_ = sshClient.SendKeepAlive()
				}
			case <-done:
				return
			}
		}
	}()

	var wg sync.WaitGroup
	wg.Add(1)
	// Read from SSH stdout and send to WebSocket
	go func() {
		defer wg.Done()
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Stdout Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
				closeDone()
			}
		}()
		buf := make([]byte, 1024)
		start := time.Now()
		for {
			n, err := stdout.Read(buf)
			if n > 0 {
				data := buf[:n]
				if recordBuf != nil {
					// Store as [time_offset, "o", "data"]
					offset := time.Since(start).Seconds()
					entry, _ := json.Marshal([]interface{}{offset, "o", string(data)})
					recordBuf.Write(entry)
					recordBuf.WriteString("\n")
				}
				if err := writeParams(websocket.BinaryMessage, data); err != nil {
					utils.LogError("Error writing to WebSocket: %v", err)
					closeDone()
					return
				}
			}
			if err != nil {
				if err != io.EOF {
					utils.LogError("Error reading from stdout: %v", err)
				}
				closeDone()
				return
			}
		}
	}()

	// Read from SSH stderr and send to WebSocket
	go func() {
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Stderr Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
			}
		}()
		buf := make([]byte, 1024)
		for {
			n, err := stderr.Read(buf)
			if n > 0 {
				if err := writeParams(websocket.BinaryMessage, buf[:n]); err != nil {
					utils.LogError("Error writing to WebSocket: %v", err)
					return
				}
			}
			if err != nil {
				if err != io.EOF {
					utils.LogError("Error reading from stderr: %v", err)
				}
				return
			}
		}
	}()

	// Read from WebSocket and send to SSH stdin
	go func() {
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Stdin Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
				closeDone() // Ensure we close cleanup
			}
		}()
		for {
			if idleTimeout > 0 {
				ws.SetReadDeadline(time.Now().Add(idleTimeout))
			}
			messageType, message, err := ws.ReadMessage()
			if err != nil {
				if isTimeoutError(err) {
					closeDoneWithReason(wsCloseCodeIdleTimeout, "idle timeout")
					return
				}
				if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
					utils.LogError("Error reading from WebSocket: %v", err)
				}
				closeDone()
				return
			}

			if messageType == websocket.TextMessage {
				// Try to parse as JSON message
				var wsMsg WSMessage
				if err := json.Unmarshal(message, &wsMsg); err == nil {
					// Handle structured messages
					switch wsMsg.Type {
					case "resize":
						var resizeData ResizeData
						dataBytes, _ := json.Marshal(wsMsg.Data)
						if err := json.Unmarshal(dataBytes, &resizeData); err == nil {
							sshClient.Resize(resizeData.Rows, resizeData.Cols)
						}
					case "input":
						if data, ok := wsMsg.Data.(string); ok {
							stdin.Write([]byte(data))
						}
					}
				} else {
					// Handle plain text input
					stdin.Write(message)
				}
			} else if messageType == websocket.PongMessage {
				// Pong received, reset deadline (handled by SetReadDeadline above implicitly on next read)
				// Actually, ReadMessage handles Ping/Pong control messages mostly automatically,
				// but we need to ensure our idle timeout is reset.
				// Since we call SetReadDeadline before ReadMessage, any message including Pong will allow the loop to continue.
			}
		}
	}()

	// Wait for completion
	<-done

	// 1. Explicitly close connections to break blocking reads
	if sshClient != nil {
		_ = sshClient.Close()
	}
	_ = writeParams(websocket.CloseMessage, websocket.FormatCloseMessage(closeCode, closeReason))
	_ = ws.Close()

	// 2. Wait for stdout goroutine to exit safely
	wg.Wait()

	// 3. Now safe to finalize recording without data race
	if recordBuf != nil {
		_ = recordBuf.Flush()
		if recording != nil {
			now := time.Now()
			recording.EndTime = &now
			recording.Duration = int(now.Sub(recording.StartTime).Seconds())
			h.saveDB(recording)
		}
	}

	// Update connection log
	now := time.Now()
	connLog.DisconnectedAt = &now
	connLog.Duration = int(now.Sub(connLog.ConnectedAt).Seconds())
	connLog.Status = "disconnected"
	h.saveDB(connLog)

	log.Printf("SSH session closed for user %d, host %s", userID, host.Host)
}
