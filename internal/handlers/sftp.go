package handlers

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/ssh"
	"github.com/ihxw/termiscope/internal/utils"
	"github.com/pkg/sftp"
	cryptossh "golang.org/x/crypto/ssh"
	"gorm.io/gorm"
)

type SftpHandler struct {
	db     *gorm.DB
	config *config.Config
}

func NewSftpHandler(db *gorm.DB, cfg *config.Config) *SftpHandler {
	return &SftpHandler{
		db:     db,
		config: cfg,
	}
}

// saveDB safely saves a record, logging errors without failing
func (h *SftpHandler) saveDB(value interface{}) {
	if err := h.db.Save(value).Error; err != nil {
		utils.LogError("DB save failed: %v", err)
	}
}

type FileInfo struct {
	Name    string    `json:"name"`
	Size    int64     `json:"size"`
	Mode    uint32    `json:"mode"`
	ModTime time.Time `json:"mod_time"`
	IsDir   bool      `json:"is_dir"`
}

// logAudit internal helper
func (h *SftpHandler) logAudit(userID uint, hostID, action, srcPath, destPath, ip string, opErr error) {
	hostIDUint, _ := strconv.ParseUint(hostID, 10, 32)
	status := "success"
	errMsg := ""
	if opErr != nil {
		status = "failed"
		errMsg = opErr.Error()
	}
	
	audit := models.SftpAuditLog{
		UserID:     userID,
		HostID:     uint(hostIDUint),
		Action:     action,
		SourcePath: srcPath,
		DestPath:   destPath,
		ClientIP:   ip,
		Status:     status,
		ErrorMsg:   errMsg,
	}
	h.db.Create(&audit)
}

// getSftpClient helper to create an SFTP client for a host
func (h *SftpHandler) getSftpClient(userID uint, hostID string) (*sftp.Client, *ssh.SSHClient, error) {
	// Get SSH host from database
	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", hostID, userID).First(&host).Error; err != nil {
		return nil, nil, fmt.Errorf("host not found")
	}

	// Decrypt credentials
	password, privateKey := decryptHostCredentials(&host, h.config.Security.EncryptionKey)

	// Create SSH client
	timeout, _ := time.ParseDuration(h.config.SSH.Timeout)
	if timeout == 0 {
		timeout = 30 * time.Second
	}

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
		return nil, nil, fmt.Errorf("failed to create SSH client: %w", err)
	}

	if err := sshClient.Connect(); err != nil {
		errMsg := err.Error()
		// Check for host key fingerprint mismatch
		if strings.Contains(errMsg, "host key fingerprint mismatch") {
			newFp := sshClient.GetFingerprint()
			return nil, nil, fmt.Errorf("FINGERPRINT_MISMATCH:%s", newFp)
		}
		return nil, nil, fmt.Errorf("failed to connect: %w", err)
	}

	// TOFU: Save fingerprint if it was empty
	if host.Fingerprint == "" {
		newFp := sshClient.GetFingerprint()
		if newFp != "" {
			host.Fingerprint = newFp
			h.saveDB(&host)
		}
	}

	// Create SFTP client
	sftpClient, err := sftp.NewClient(sshClient.GetRawClient())
	if err != nil {
		sshClient.Close()
		return nil, nil, fmt.Errorf("failed to create SFTP client: %w", err)
	}

	return sftpClient, sshClient, nil
}

// List handled GET /api/sftp/list/:hostId?path=...
func (h *SftpHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	path := c.DefaultQuery("path", ".")

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	files, err := sftpClient.ReadDir(path)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to read directory: "+err.Error())
		return
	}

	// Resolve absolute path for frontend breadcrumbs
	realPath, err := sftpClient.RealPath(path)
	if err != nil {
		// Log error but continue with relative path? Or strict error?
		// Fallback to path if realpath fails (unlikely if ReadDir succeeded)
		realPath = path
	}
	// For Windows SFTP servers, ensure forward slashes
	realPath = filepath.ToSlash(realPath)

	var result []FileInfo
	for _, f := range files {
		result = append(result, FileInfo{
			Name:    f.Name(),
			Size:    f.Size(),
			Mode:    uint32(f.Mode()),
			ModTime: f.ModTime(),
			IsDir:   f.IsDir(),
		})
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"files": result,
		"cwd":   realPath,
	})
}

// Download handles GET /api/sftp/download/:hostId?path=...
func (h *SftpHandler) Download(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	targetPath := c.Query("path")

	if targetPath == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "path is required")
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	stat, err := sftpClient.Stat(targetPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to stat file: "+err.Error())
		return
	}

	if stat.IsDir() {
		// Directory Download: Stream Zip
		c.Header("Content-Disposition", "attachment; filename="+path.Base(targetPath)+".zip")
		c.Header("Content-Type", "application/zip")
		// Disable buffering/chunking middleware interference if any, though Gin handles it well.

		zw := zip.NewWriter(c.Writer)
		defer zw.Close()

		walker := sftpClient.Walk(targetPath)
		for walker.Step() {
			if err := walker.Err(); err != nil {
				// Log error but continue?
				continue
			}

			fileInfo := walker.Stat()
			filePath := walker.Path()

			// Skip the root dir itself to avoid empty entry with dot name
			if filePath == targetPath {
				continue
			}

			// Calculate relative path for zip structure
			relPath, err := filepath.Rel(targetPath, filePath)
			if err != nil {
				continue
			}
			relPath = filepath.ToSlash(relPath) // Zip uses forward slashes

			// Create zip header
			header, err := zip.FileInfoHeader(fileInfo)
			if err != nil {
				continue
			}
			header.Name = relPath

			if fileInfo.IsDir() {
				header.Name += "/"
				header.Method = zip.Store
			} else {
				header.Method = zip.Deflate
			}

			writer, err := zw.CreateHeader(header)
			if err != nil {
				continue
			}

			if !fileInfo.IsDir() {
				f, err := sftpClient.Open(filePath)
				if err != nil {
					continue
				}
				io.Copy(writer, f)
				f.Close()
			}
		}
		return
	}

	// File Download
	file, err := sftpClient.Open(targetPath)
	if err != nil {
		h.logAudit(userID, hostID, "download", targetPath, "", c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to open file: "+err.Error())
		return
	}
	defer file.Close()

	h.logAudit(userID, hostID, "download", targetPath, "", c.ClientIP(), nil)

	// Use ServeContent to handle Range requests and streaming
	c.Header("Content-Disposition", "attachment; filename="+path.Base(targetPath))
	// Content-Type will be sniffed by ServeContent or we can set it if we knew it.
	// But usually ServeContent handles it.
	// We can let ServeContent guess or set generic.
	// Actually ServeContent sniffs from filename extension or content.

	http.ServeContent(c.Writer, c.Request, path.Base(targetPath), stat.ModTime(), file)
}

// Upload handles POST /api/sftp/upload/:hostId
func (h *SftpHandler) Upload(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	remotePath := c.PostForm("path")

	if remotePath == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "path is required")
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "failed to get file: "+err.Error())
		return
	}
	defer file.Close()

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	// Sanitize filename to prevent path traversal
	cleanFilename := filepath.Base(header.Filename)
	fullPath := filepath.Join(remotePath, cleanFilename)
	fullPath = filepath.ToSlash(fullPath) // Ensure forward slashes for Linux remotes

	dst, err := sftpClient.Create(fullPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create remote file: "+err.Error())
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		h.logAudit(userID, hostID, "upload", fullPath, "", c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy file: "+err.Error())
		return
	}

	h.logAudit(userID, hostID, "upload", fullPath, "", c.ClientIP(), nil)
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "file uploaded successfully"})
}

// deleteRecursive handles recursive deletion of files and directories
func (h *SftpHandler) deleteRecursive(client *sftp.Client, remotePath string) error {
	stat, err := client.Stat(remotePath)
	if err != nil {
		return err
	}

	if !stat.IsDir() {
		return client.Remove(remotePath)
	}

	// It's a directory, list contents
	files, err := client.ReadDir(remotePath)
	if err != nil {
		return err
	}

	for _, file := range files {
		// Use simple string concatenation or path.Join to ensure forward slashes for SFTP
		// filepath.Join might use backslashes on Windows which can confuse some SFTP servers
		childPath := filepath.ToSlash(filepath.Join(remotePath, file.Name()))
		if err := h.deleteRecursive(client, childPath); err != nil {
			return err
		}
	}

	return client.RemoveDirectory(remotePath)
}

// Delete handles DELETE /api/sftp/delete/:hostId?path=...
func (h *SftpHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	path := c.Query("path")

	if path == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "path is required")
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	// Use recursive delete to handle both files and non-empty directories
	err = h.deleteRecursive(sftpClient, path)
	if err != nil {
		h.logAudit(userID, hostID, "delete", path, "", c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete: "+err.Error())
		return
	}

	h.logAudit(userID, hostID, "delete", path, "", c.ClientIP(), nil)
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "deleted successfully"})
}

// Rename handles POST /api/sftp/rename/:hostId
func (h *SftpHandler) Rename(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")

	var req struct {
		OldPath string `json:"old_path" binding:"required"`
		NewPath string `json:"new_path" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	if err := sftpClient.Rename(req.OldPath, req.NewPath); err != nil {
		h.logAudit(userID, hostID, "rename", req.OldPath, req.NewPath, c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to rename: "+err.Error())
		return
	}

	h.logAudit(userID, hostID, "rename", req.OldPath, req.NewPath, c.ClientIP(), nil)
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "renamed successfully"})
}

// Paste handles POST /api/sftp/paste/:hostId
func (h *SftpHandler) Paste(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")

	var req struct {
		Source string `json:"source" binding:"required"`
		Dest   string `json:"dest" binding:"required"`
		Type   string `json:"type" binding:"required,oneof=cut copy"` // cut or copy
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	// Calculate new path
	fileName := path.Base(req.Source)
	newPath := filepath.ToSlash(filepath.Join(req.Dest, fileName))

	if req.Source == newPath {
		utils.ErrorResponse(c, http.StatusBadRequest, "cannot paste into same location")
		return
	}

	if req.Type == "cut" {
		// Move is simple rename
		if err := sftpClient.Rename(req.Source, newPath); err != nil {
			h.logAudit(userID, hostID, "move", req.Source, newPath, c.ClientIP(), err)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to move: "+err.Error())
			return
		}
		h.logAudit(userID, hostID, "move", req.Source, newPath, c.ClientIP(), nil)
	} else {
		// Copy is recursive
		if err := h.copyRecursive(sftpClient, req.Source, newPath); err != nil {
			h.logAudit(userID, hostID, "copy", req.Source, newPath, c.ClientIP(), err)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy: "+err.Error())
			return
		}
		h.logAudit(userID, hostID, "copy", req.Source, newPath, c.ClientIP(), nil)
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "pasted successfully"})
}

func (h *SftpHandler) copyRecursive(client *sftp.Client, src, dst string) error {
	stat, err := client.Stat(src)
	if err != nil {
		return err
	}

	if stat.IsDir() {
		// Create dest dir
		if err := client.MkdirAll(dst); err != nil {
			// If exists, it's fine
			if _, err := client.Stat(dst); err != nil {
				return err
			}
		}

		entries, err := client.ReadDir(src)
		if err != nil {
			return err
		}

		for _, entry := range entries {
			srcPath := filepath.ToSlash(filepath.Join(src, entry.Name()))
			dstPath := filepath.ToSlash(filepath.Join(dst, entry.Name()))
			if err := h.copyRecursive(client, srcPath, dstPath); err != nil {
				return err
			}
		}
	} else {
		// Copy file
		srcFile, err := client.Open(src)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		dstFile, err := client.Create(dst)
		if err != nil {
			return err
		}
		defer dstFile.Close()

		if _, err := srcFile.WriteTo(dstFile); err != nil {
			return err
		}
		// Preserve mode
		client.Chmod(dst, stat.Mode())
	}
	return nil
}

// Mkdir handles POST /api/sftp/mkdir/:hostId
func (h *SftpHandler) Mkdir(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")

	var req struct {
		Path string `json:"path" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	if err := sftpClient.Mkdir(req.Path); err != nil {
		h.logAudit(userID, hostID, "mkdir", req.Path, "", c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create directory: "+err.Error())
		return
	}

	h.logAudit(userID, hostID, "mkdir", req.Path, "", c.ClientIP(), nil)
	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "directory created successfully"})
}

// CreateFile handles POST /api/sftp/create/:hostId
func (h *SftpHandler) CreateFile(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")

	var req struct {
		Path string `json:"path" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	file, err := sftpClient.Create(req.Path)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create file: "+err.Error())
		return
	}
	file.Close()

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "file created successfully"})
}

// GetDirSize handles GET /api/sftp/size/:hostId?path=...
func (h *SftpHandler) GetDirSize(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	targetPath := c.Query("path")

	if targetPath == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "path is required")
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	// Try du -s via SSH first (faster)
	session, err := sshClient.GetRawClient().NewSession()
	if err == nil {
		defer session.Close()
		// Attempt to get size in kilobytes with shell escaping
		// Note: -k is widely supported (POSIX). -b is GNU specific.
		escapedPath := utils.ShellEscape(targetPath)
		output, err := session.Output("du -sk " + escapedPath)
		if err == nil {
			// Output format: "12345   /path/to/dir"
			fields := strings.Fields(string(output))
			if len(fields) > 0 {
				var sizeKB int64
				if _, err := fmt.Sscanf(fields[0], "%d", &sizeKB); err == nil {
					utils.SuccessResponse(c, http.StatusOK, gin.H{
						"size":   sizeKB * 1024,
						"method": "du",
					})
					return
				}
			}
		}
	}

	// Fallback: SFTP Walk (Slower but reliable if shell access restricted)
	var size int64
	walker := sftpClient.Walk(targetPath)
	for walker.Step() {
		if err := walker.Err(); err != nil {
			continue
		}
		if !walker.Stat().IsDir() {
			size += walker.Stat().Size()
		}
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"size":   size,
		"method": "scan",
	})
}

// sendTransferEvent writes a JSON event line and flushes for streaming
func sendTransferEvent(c *gin.Context, data map[string]interface{}) {
	jsonBytes, _ := json.Marshal(data)
	c.Writer.Write(jsonBytes)
	c.Writer.Write([]byte("\n"))
	c.Writer.(http.Flusher).Flush()
}

// Transfer handles POST /api/sftp/transfer
// Preferred: direct SCP from source VPS to dest VPS (data bypasses this server)
// Fallback: server-side relay when sshpass is not available for password auth
func (h *SftpHandler) Transfer(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		SourceHostID string `json:"source_host_id" binding:"required"`
		DestHostID   string `json:"dest_host_id" binding:"required"`
		SourcePath   string `json:"source_path" binding:"required"`
		DestPath     string `json:"dest_path" binding:"required"`
		Type         string `json:"type" binding:"omitempty,oneof=cut copy"` // cut or copy
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	// Get destination host info and decrypt credentials (needed for SCP command)
	var dstHost models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", req.DestHostID, userID).First(&dstHost).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "destination host not found")
		return
	}
	var dstPassword, dstPrivateKey string
	if dstHost.PasswordEncrypted != "" {
		dec, err := utils.DecryptAES(dstHost.PasswordEncrypted, h.config.Security.EncryptionKey)
		if err == nil {
			dstPassword = dec
		}
	}
	if dstHost.PrivateKeyEncrypted != "" {
		dec, err := utils.DecryptAES(dstHost.PrivateKeyEncrypted, h.config.Security.EncryptionKey)
		if err == nil {
			dstPrivateKey = dec
		}
	}

	// Set up NDJSON streaming response
	c.Header("Content-Type", "application/x-ndjson")
	c.Header("Cache-Control", "no-cache")
	c.Header("X-Accel-Buffering", "no")

	// Connect to source via SFTP to get file info
	srcSftp, srcSSH, err := h.getSftpClient(userID, req.SourceHostID)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to connect to source: " + err.Error()})
		return
	}
	defer srcSSH.Close()

	srcStat, err := srcSftp.Stat(req.SourcePath)
	if err != nil {
		srcSftp.Close()
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "source path not found: " + err.Error()})
		return
	}
	isDir := srcStat.IsDir()
	totalSize := srcStat.Size()
	if isDir {
		totalSize = 0
		walker := srcSftp.Walk(req.SourcePath)
		for walker.Step() {
			if walker.Err() == nil && !walker.Stat().IsDir() {
				totalSize += walker.Stat().Size()
			}
		}
	}
	srcSftp.Close()

	fileName := path.Base(req.SourcePath)
	sendTransferEvent(c, map[string]interface{}{
		"type": "start", "total_size": totalSize, "is_dir": isDir, "file_name": fileName,
	})

	// Try direct SCP from source to destination
	if h.tryDirectSCP(c, srcSSH, dstHost, dstPassword, dstPrivateKey, req.SourcePath, req.DestPath, isDir) {
		return
	}

	// Fallback: server-side relay with progress
	sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "using server relay"})
	relayErr := h.transferViaRelay(c, userID, req.SourceHostID, req.DestHostID, req.SourcePath, req.DestPath, totalSize)

	// If cut requested and transfer succeeded, delete source
	if req.Type == "cut" && relayErr == nil {
		srcSftp, srcSSH, err := h.getSftpClient(userID, req.SourceHostID)
		if err == nil {
			h.deleteRecursive(srcSftp, req.SourcePath)
			srcSftp.Close()
			srcSSH.Close()
		}
	}
}

// tryDirectSCP runs scp from source VPS directly to dest VPS. Returns true if attempted.
func (h *SftpHandler) tryDirectSCP(c *gin.Context, srcSSH *ssh.SSHClient, dstHost models.SSHHost, dstPassword, dstPrivateKey, sourcePath, destPath string, isDir bool) bool {
	rawClient := srcSSH.GetRawClient()

	var scpAuthPrefix, cleanupCmd string

	if dstPrivateKey != "" {
		// Key auth: write temp key to source VPS
		setupSession, err := rawClient.NewSession()
		if err != nil {
			return false
		}
		escapedKey := strings.ReplaceAll(dstPrivateKey, "'", "'\\''")
		cmd := fmt.Sprintf("TMPKEY=$(mktemp /tmp/ts_key_XXXXXX) && chmod 600 $TMPKEY && printf '%%s' '%s' > $TMPKEY && echo $TMPKEY", escapedKey)
		output, err := setupSession.Output(cmd)
		setupSession.Close()
		if err != nil {
			return false
		}
		tmpKeyPath := strings.TrimSpace(string(output))
		if tmpKeyPath == "" || !strings.HasPrefix(tmpKeyPath, "/tmp/ts_key_") {
			return false
		}
		scpAuthPrefix = fmt.Sprintf("scp -i %s", utils.ShellEscape(tmpKeyPath))
		cleanupCmd = fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpKeyPath))
	} else if dstPassword != "" {
		// Check sshpass availability
		checkSession, err := rawClient.NewSession()
		if err != nil {
			return false
		}
		_, err = checkSession.Output("command -v sshpass")
		checkSession.Close()
		if err != nil {
			sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "sshpass not available, falling back to relay"})
			return false
		}
		// Security: Write password to temp file instead of command line to avoid /proc exposure
		passSession, err := rawClient.NewSession()
		if err != nil {
			return false
		}
		escapedPass := strings.ReplaceAll(dstPassword, "'", "'\\''")
		passCmd := fmt.Sprintf("TMPPASS=$(mktemp /tmp/ts_pass_XXXXXX) && chmod 600 $TMPPASS && printf '%%s' '%s' > $TMPPASS && echo $TMPPASS", escapedPass)
		passOutput, err := passSession.Output(passCmd)
		passSession.Close()
		if err != nil {
			return false
		}
		tmpPassPath := strings.TrimSpace(string(passOutput))
		if tmpPassPath == "" || !strings.HasPrefix(tmpPassPath, "/tmp/ts_pass_") {
			return false
		}
		scpAuthPrefix = fmt.Sprintf("sshpass -f %s scp", utils.ShellEscape(tmpPassPath))
		cleanupCmd = fmt.Sprintf("rm -f %s", utils.ShellEscape(tmpPassPath))
	} else {
		return false
	}

	// Security: SCP Host Key Verification via ssh-keyscan and verify against DB fingerprint
	expectedFp := dstHost.Fingerprint
	// Fallback empty fingerprint checking if not populated (not recommended, but failsafe)
	fingerprintCheck := ""
	if expectedFp != "" {
		expectedFpStr := strings.ReplaceAll(expectedFp, "'", "'\\''")
		fingerprintCheck = fmt.Sprintf(`
TMP_HOSTS=$(mktemp /tmp/ts_hosts_XXXXXX)
ssh-keyscan -p %d %s > $TMP_HOSTS 2>/dev/null
SCANNED_FP=$(ssh-keygen -l -f $TMP_HOSTS 2>/dev/null | awk '{print $2}' | head -n 1)
if [ "$SCANNED_FP" != '%s' ]; then
	echo "TRANSFER_ERROR: destination host key fingerprint mismatch (expected '%s', got $SCANNED_FP)" >&2
	rm -f $TMP_HOSTS
	%s
	exit 1
fi`, dstHost.Port, utils.ShellEscape(dstHost.Host), expectedFpStr, expectedFpStr, cleanupCmd)
	} else {
		// If no fingerprint in DB (rare TOFU), just grab it to bypass strict checking prompt, but warn
		fingerprintCheck = fmt.Sprintf("TMP_HOSTS=$(mktemp /tmp/ts_hosts_XXXXXX)\nssh-keyscan -p %d %s > $TMP_HOSTS 2>/dev/null", dstHost.Port, utils.ShellEscape(dstHost.Host))
	}

	scpFlags := "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=$TMP_HOSTS"
	if isDir {
		scpFlags += " -r"
	}

	scpCmd := fmt.Sprintf("%s\n%s %s -P %d %s %s@%s:%s\nrm -f $TMP_HOSTS",
		fingerprintCheck,
		scpAuthPrefix, scpFlags, dstHost.Port,
		utils.ShellEscape(sourcePath), dstHost.Username, dstHost.Host, utils.ShellEscape(destPath+"/"))

	// Run with PTY for progress output
	session, err := rawClient.NewSession()
	if err != nil {
		return false
	}
	defer session.Close()

	modes := cryptossh.TerminalModes{cryptossh.ECHO: 0}
	if err := session.RequestPty("xterm", 40, 200, modes); err != nil {
		return false
	}

	stdout, err := session.StdoutPipe()
	if err != nil {
		return false
	}
	if err := session.Start(scpCmd); err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "SCP start failed: " + err.Error()})
		return true
	}

	// Parse SCP progress output
	progressRe := regexp.MustCompile(`(\d+)%\s+(\S+)\s+(\S+/s)`)
	buf := make([]byte, 4096)
	var lastPercent int
	for {
		n, readErr := stdout.Read(buf)
		if n > 0 {
			for _, part := range strings.Split(string(buf[:n]), "\r") {
				if matches := progressRe.FindStringSubmatch(part); len(matches) >= 4 {
					var pct int
					fmt.Sscanf(matches[1], "%d", &pct)
					if pct != lastPercent {
						lastPercent = pct
						sendTransferEvent(c, map[string]interface{}{
							"type": "progress", "percent": pct, "speed": matches[3],
						})
					}
				}
			}
		}
		if readErr != nil {
			break
		}
	}

	exitErr := session.Wait()

	// Cleanup temp credentials
	if cleanupCmd != "" {
		if cs, err := rawClient.NewSession(); err == nil {
			cs.Run(cleanupCmd)
			cs.Close()
		}
	}

	if exitErr != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "SCP failed: " + exitErr.Error()})
	} else {
		sendTransferEvent(c, map[string]interface{}{"type": "complete", "method": "direct"})
	}
	return true
}

// transferViaRelay uses server-side SFTP relay with progress streaming
func (h *SftpHandler) transferViaRelay(c *gin.Context, userID uint, srcHostID, dstHostID, sourcePath, destPath string, totalSize int64) error {
	srcSftp, srcSSH, err := h.getSftpClient(userID, srcHostID)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "relay connect source failed: " + err.Error()})
		return err
	}
	defer srcSftp.Close()
	defer srcSSH.Close()

	dstSftp, dstSSH, err := h.getSftpClient(userID, dstHostID)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "relay connect dest failed: " + err.Error()})
		return err
	}
	defer dstSftp.Close()
	defer dstSSH.Close()

	srcStat, err := srcSftp.Stat(sourcePath)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "source not found: " + err.Error()})
		return err
	}

	fileName := path.Base(sourcePath)
	destFullPath := filepath.ToSlash(filepath.Join(destPath, fileName))

	var transferred int64
	var lastPct int
	startTime := time.Now()
	var lastSpeed float64
	
	onProgress := func(n int64) {
		transferred += n
		elapsed := time.Since(startTime).Seconds()
		
		// Calculate speed (bytes per second)
		currentSpeed := float64(transferred) / elapsed
		// Smooth speed calculation
		lastSpeed = lastSpeed*0.7 + currentSpeed*0.3
		
		if totalSize > 0 {
			pct := int(transferred * 100 / totalSize)
			if pct != lastPct {
				lastPct = pct
				// Format speed
				speedStr := formatSpeed(lastSpeed)
				sendTransferEvent(c, map[string]interface{}{
					"type": "progress", 
					"percent": pct,
					"speed": speedStr,
					"transferred": transferred,
					"total": totalSize,
				})
			}
		}
	}

	var transferErr error
	if srcStat.IsDir() {
		transferErr = h.relayRecursive(srcSftp, dstSftp, sourcePath, destFullPath, onProgress)
	} else {
		transferErr = h.relaySingleFile(srcSftp, dstSftp, sourcePath, destFullPath, onProgress)
	}

	if transferErr != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "relay: " + transferErr.Error()})
		return transferErr
	}
	sendTransferEvent(c, map[string]interface{}{"type": "complete", "method": "relay"})
	return nil
}

// formatSpeed formats bytes per second to human readable string
func formatSpeed(bytesPerSec float64) string {
	if bytesPerSec < 1024 {
		return fmt.Sprintf("%.1f B/s", bytesPerSec)
	} else if bytesPerSec < 1024*1024 {
		return fmt.Sprintf("%.1f KB/s", bytesPerSec/1024)
	} else if bytesPerSec < 1024*1024*1024 {
		return fmt.Sprintf("%.1f MB/s", bytesPerSec/(1024*1024))
	}
	return fmt.Sprintf("%.1f GB/s", bytesPerSec/(1024*1024*1024))
}

func (h *SftpHandler) relaySingleFile(src, dst *sftp.Client, srcPath, dstPath string, onProgress func(int64)) error {
	srcFile, err := src.Open(srcPath)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	dstFile, err := dst.Create(dstPath)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	// Use larger buffer for better performance (256KB)
	buf := make([]byte, 256*1024)
	totalWritten := int64(0)
	
	for {
		n, readErr := srcFile.Read(buf)
		if n > 0 {
			written, wErr := dstFile.Write(buf[:n])
			if wErr != nil {
				return wErr
			}
			totalWritten += int64(written)
			if onProgress != nil {
				onProgress(int64(written))
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return readErr
		}
	}

	if stat, err := src.Stat(srcPath); err == nil {
		dst.Chmod(dstPath, stat.Mode())
	}
	return nil
}

func (h *SftpHandler) relayRecursive(src, dst *sftp.Client, srcPath, dstPath string, onProgress func(int64)) error {
	stat, err := src.Stat(srcPath)
	if err != nil {
		return fmt.Errorf("stat failed: %w", err)
	}
	
	if stat.IsDir() {
		if err := dst.MkdirAll(dstPath); err != nil {
			if _, e := dst.Stat(dstPath); e != nil {
				return fmt.Errorf("mkdir failed: %w", err)
			}
		}
		entries, err := src.ReadDir(srcPath)
		if err != nil {
			return fmt.Errorf("readdir failed: %w", err)
		}
		for _, entry := range entries {
			s := filepath.ToSlash(filepath.Join(srcPath, entry.Name()))
			d := filepath.ToSlash(filepath.Join(dstPath, entry.Name()))
			if err := h.relayRecursive(src, dst, s, d, onProgress); err != nil {
				return err
			}
		}
	} else {
		// Retry logic for single file transfer
		maxRetries := 3
		var lastErr error
		for attempt := 0; attempt < maxRetries; attempt++ {
			lastErr = h.relaySingleFile(src, dst, srcPath, dstPath, onProgress)
			if lastErr == nil {
				return nil
			}
			// Wait before retry (exponential backoff)
			if attempt < maxRetries-1 {
				time.Sleep(time.Duration(attempt+1) * time.Second)
			}
		}
		return fmt.Errorf("transfer failed after %d attempts: %w", maxRetries, lastErr)
	}
	return nil
}
