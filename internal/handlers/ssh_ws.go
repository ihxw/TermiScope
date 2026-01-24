package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime/debug"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/ssh"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// This will be set by handler with allowed origins from config
		return true // Placeholder, actual check done in handler
	},
	EnableCompression: true,
}

// createUpgrader creates a WebSocket upgrader with origin validation
func createUpgrader(allowedOrigins []string) websocket.Upgrader {
	return websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")

			// Allow requests with no origin (same-origin requests in production)
			if origin == "" {
				return true
			}

			// Check if origin matches the request host (same-origin)
			// This handles production scenarios where frontend is served by the same server
			host := r.Header.Get("Host")
			if host != "" {
				// Compare origin without protocol
				requestOrigin := "http://" + host
				if origin == requestOrigin || origin == "https://"+host {
					return true
				}
			}

			// If allowed_origins is empty, only allow same-origin (production mode)
			if len(allowedOrigins) == 0 {
				return false
			}

			// Check if origin is in the allowed list (development mode)
			for _, allowed := range allowedOrigins {
				if allowed == "*" || origin == allowed {
					return true
				}
			}

			return false
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

type WSMessage struct {
	Type string      `json:"type"` // input, resize
	Data interface{} `json:"data"`
}

type ResizeData struct {
	Rows int `json:"rows"`
	Cols int `json:"cols"`
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

	// Decrypt credentials
	var password, privateKey string
	if host.PasswordEncrypted != "" {
		decrypted, err := utils.DecryptAES(host.PasswordEncrypted, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to decrypt password")
			return
		}
		password = decrypted
	}
	if host.PrivateKeyEncrypted != "" {
		decrypted, err := utils.DecryptAES(host.PrivateKeyEncrypted, h.config.Security.EncryptionKey)
		if err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to decrypt private key")
			return
		}
		privateKey = decrypted
	}

	// Create upgrader with origin validation
	upgrader := createUpgrader(h.config.Server.AllowedOrigins)

	// Upgrade to WebSocket
	ws, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade to WebSocket: %v", err)
		return
	}
	defer ws.Close()

	// Parse timeout
	timeout, err := time.ParseDuration(h.config.SSH.Timeout)
	if err != nil {
		timeout = 30 * time.Second
	}

	// Parse idle timeout
	idleTimeout, err := time.ParseDuration(h.config.SSH.IdleTimeout)
	if err != nil {
		idleTimeout = 30 * time.Minute
	}

	// Create SSH client
	sshClient, err := ssh.NewSSHClient(&ssh.SSHConfig{
		Host:        host.Host,
		Port:        host.Port,
		Username:    host.Username,
		Password:    password,
		PrivateKey:  privateKey,
		Timeout:     timeout,
		Fingerprint: host.Fingerprint,
	})
	if err != nil {
		ws.WriteJSON(gin.H{"type": "error", "data": "Failed to create SSH client: " + err.Error()})
		return
	}
	defer sshClient.Close()

	// ... connLog ... (omitted creation to keep context short, but assuming it follows)
	// Actually I need to match enough context.
	// Let's match from Create SSH client to Connect.

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
	h.db.Create(connLog)

	// Connect to SSH server
	if err := sshClient.Connect(); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)

		// Check for host key mismatch
		if err.Error() == "host key fingerprint mismatch" || (len(err.Error()) > 29 && err.Error()[:29] == "host key fingerprint mismatch") {
			// Extract the new fingerprint from the error or client
			// The error message format is "host key fingerprint mismatch: anticipated %s, got %s"
			// But we can also get it from client.GetFingerprint() because the callback sets it even on error?
			// Let's check client implementation. The callback sets client.fingerprint = fp BEFORE returning error.
			newFp := sshClient.GetFingerprint()
			writeJSON(gin.H{
				"type": "error",
				"code": "fingerprint_mismatch",
				"data": fmt.Sprintf("Host key verification failed. The remote host identification has changed! New fingerprint: %s", newFp),
				"meta": gin.H{
					"new_fingerprint": newFp,
				},
			})
		} else {
			writeJSON(gin.H{"type": "error", "data": "Failed to connect (Host Verification Failed): " + err.Error()})
		}
		return
	}

	// TOFU: Save fingerprint if it was empty
	if host.Fingerprint == "" {
		newFp := sshClient.GetFingerprint()
		if newFp != "" {
			host.Fingerprint = newFp
			h.db.Save(&host)
			log.Printf("TOFU: Saved new fingerprint for host %s: %s", host.Host, newFp)
		}
	}

	// Create session
	if err := sshClient.NewSession(); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to create session: " + err.Error()})
		return
	}

	session := sshClient.GetSession()

	// Request PTY
	if err := sshClient.RequestPTY("xterm-256color", 24, 80); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to request PTY: " + err.Error()})
		return
	}

	// Set up pipes
	stdin, err := session.StdinPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stdin pipe: " + err.Error()})
		return
	}

	stdout, err := session.StdoutPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stdout pipe: " + err.Error()})
		return
	}

	stderr, err := session.StderrPipe()
	if err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to get stderr pipe: " + err.Error()})
		return
	}

	// Start shell
	if err := sshClient.Shell(); err != nil {
		connLog.Status = "failed"
		connLog.ErrorMessage = err.Error()
		h.db.Save(connLog)
		writeJSON(gin.H{"type": "error", "data": "Failed to start shell: " + err.Error()})
		return
	}

	// Update connection log
	connLog.Status = "success"
	h.db.Save(connLog)

	// Send success message
	writeJSON(gin.H{"type": "connected", "data": "Connected successfully"})

	// Channel to signal completion
	done := make(chan bool)

	// Handle recording
	record := c.Query("record") == "true"
	var recording *models.TerminalRecording
	var recordFile *os.File
	if record {
		recordingDir := "data/recordings"
		os.MkdirAll(recordingDir, 0755)

		fileName := fmt.Sprintf("%d-%d-%d.cast", userID, host.ID, time.Now().Unix())
		filePath := filepath.Join(recordingDir, fileName)

		f, err := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err == nil {
			recordFile = f
			recording = &models.TerminalRecording{
				UserID:    userID,
				SSHHostID: host.ID,
				Host:      host.Host,
				Username:  host.Username,
				FilePath:  filePath,
				StartTime: time.Now(),
			}
			h.db.Create(recording)
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
			case <-done:
				return
			}
		}
	}()

	// Read from SSH stdout and send to WebSocket
	go func() {
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Stdout Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
			}
		}()
		buf := make([]byte, 1024)
		start := time.Now()
		for {
			n, err := stdout.Read(buf)
			if err != nil {
				if err != io.EOF {
					utils.LogError("Error reading from stdout: %v", err)
				}
				done <- true
				return
			}
			if n > 0 {
				data := buf[:n]
				if recordFile != nil {
					// Store as [time_offset, "o", "data"]
					offset := time.Since(start).Seconds()
					entry, _ := json.Marshal([]interface{}{offset, "o", string(data)})
					recordFile.Write(entry)
					recordFile.WriteString("\n")
				}
				if err := writeParams(websocket.TextMessage, data); err != nil {
					utils.LogError("Error writing to WebSocket: %v", err)
					done <- true
					return
				}
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
			if err != nil {
				if err != io.EOF {
					utils.LogError("Error reading from stderr: %v", err)
				}
				return
			}
			if n > 0 {
				if err := writeParams(websocket.TextMessage, buf[:n]); err != nil {
					utils.LogError("Error writing to WebSocket: %v", err)
					return
				}
			}
		}
	}()

	// Read from WebSocket and send to SSH stdin
	go func() {
		defer func() {
			if r := recover(); r != nil {
				utils.LogError("SSH Stdin Loop Panic: %v\nStack: %s", r, string(debug.Stack()))
				done <- true // Ensure we close cleanup
			}
		}()
		for {
			if idleTimeout > 0 {
				ws.SetReadDeadline(time.Now().Add(idleTimeout))
			}
			messageType, message, err := ws.ReadMessage()
			if err != nil {
				// Don't log normal close errors or timeouts as errors to reduce noise, unless debugging
				// But user asked for "all possible errors".
				// Filter out "websocket: close 1000 (normal)"
				if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
					utils.LogError("Error reading from WebSocket: %v", err)
				}
				done <- true
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

	// Finalize recording
	if recordFile != nil {
		recordFile.Close()
		if recording != nil {
			now := time.Now()
			recording.EndTime = &now
			recording.Duration = int(now.Sub(recording.StartTime).Seconds())
			h.db.Save(recording)
		}
	}

	// Update connection log
	now := time.Now()
	connLog.DisconnectedAt = &now
	connLog.Duration = int(now.Sub(connLog.ConnectedAt).Seconds())
	connLog.Status = "disconnected"
	h.db.Save(connLog)

	log.Printf("SSH session closed for user %d, host %s", userID, host.Host)
}
