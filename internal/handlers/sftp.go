package handlers

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/config"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/ssh"
	"github.com/ihxw/termiscope/internal/utils"
	"github.com/pkg/sftp"
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

type FileInfo struct {
	Name    string    `json:"name"`
	Size    int64     `json:"size"`
	Mode    uint32    `json:"mode"`
	ModTime time.Time `json:"mod_time"`
	IsDir   bool      `json:"is_dir"`
}

type contextReader struct {
	ctx context.Context
	r   io.Reader
}

func newContextReader(ctx context.Context, r io.Reader) io.Reader {
	return contextReader{ctx: ctx, r: r}
}

func (r contextReader) Read(p []byte) (int, error) {
	select {
	case <-r.ctx.Done():
		return 0, r.ctx.Err()
	default:
	}
	return r.r.Read(p)
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

	connector := newHostConnector(h.config.Security.EncryptionKey, h.config.SSH.Timeout, func(host *models.SSHHost) error {
		return h.db.Save(host).Error
	})
	sshClient, observed, err := connector.open(&host, false)
	if err != nil {
		errMsg := err.Error()
		if strings.Contains(errMsg, "host key fingerprint mismatch") {
			return nil, nil, fmt.Errorf("FINGERPRINT_MISMATCH:%s", observed)
		}
		return nil, nil, fmt.Errorf("failed to connect: %w", err)
	}

	sftpClient, err := sftp.NewClient(
		sshClient.GetRawClient(),
		sftp.MaxPacketChecked(sftpMaxPacketSize),
		sftp.MaxConcurrentRequestsPerFile(sftpTransferConcurrency),
		sftp.UseConcurrentReads(true),
		sftp.UseConcurrentWrites(true),
		sftp.UseFstat(true),
	)
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

	// Check if path is a file
	stat, err := sftpClient.Stat(path)
	if err == nil && !stat.IsDir() {
		realPath, err := sftpClient.RealPath(path)
		if err != nil {
			realPath = path
		}
		realPath = filepath.ToSlash(realPath)
		utils.SuccessResponse(c, http.StatusOK, gin.H{
			"files":   []FileInfo{},
			"cwd":     realPath,
			"is_file": true,
		})
		return
	}

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
		// Directory Download: Stream an uncompressed tar archive.
		c.Header("Content-Disposition", "attachment; filename="+path.Base(targetPath)+".tar")
		c.Header("Content-Type", "application/x-tar")
		// Disable buffering/chunking middleware interference if any, though Gin handles it well.
		c.Header("X-Accel-Buffering", "no")

		tw := tar.NewWriter(c.Writer)
		defer tw.Close()

		walker := sftpClient.Walk(targetPath)
		for walker.Step() {
			select {
			case <-c.Request.Context().Done():
				return
			default:
			}
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

			// Calculate relative path for tar structure.
			relPath, err := filepath.Rel(targetPath, filePath)
			if err != nil {
				continue
			}
			relPath = filepath.ToSlash(relPath)

			header, err := tar.FileInfoHeader(fileInfo, "")
			if err != nil {
				continue
			}
			header.Name = relPath

			if fileInfo.IsDir() {
				header.Name += "/"
			}

			if err := tw.WriteHeader(header); err != nil {
				continue
			}

			if !fileInfo.IsDir() {
				f, err := sftpClient.Open(filePath)
				if err != nil {
					continue
				}
				_, _ = io.Copy(tw, newContextReader(c.Request.Context(), f))
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

	c.Header("Content-Disposition", "attachment; filename="+path.Base(targetPath))
	c.Header("Content-Type", "application/octet-stream")
	c.Header("Content-Length", strconv.FormatInt(stat.Size(), 10))
	c.Header("Last-Modified", stat.ModTime().UTC().Format(http.TimeFormat))
	c.Header("X-Accel-Buffering", "no")

	if _, err := file.WriteTo(c.Writer); err != nil {
		h.logAudit(userID, hostID, "download", targetPath, "", c.ClientIP(), err)
		return
	}
}

// UploadProgress tracks the status of ongoing SFTP uploads
var uploadProgressMap sync.Map

type UploadProgressData struct {
	Percent int    `json:"percent"`
	Speed   string `json:"speed"`
	Written int64  `json:"written"`
	Total   int64  `json:"total"`
}

// resolveSftpPath expands a remote path to an absolute path on the SFTP server.
func resolveSftpPath(client *sftp.Client, p string) (string, error) {
	p = strings.TrimSpace(p)
	if p == "" {
		p = "."
	}
	abs, err := client.RealPath(p)
	if err != nil {
		return "", err
	}
	return filepath.ToSlash(abs), nil
}

// joinRemotePath joins SFTP path segments with forward slashes (always use "path", not "filepath").
// dir must be an absolute directory path when possible (use resolveSftpPath first).
func joinRemotePath(dir, name string) string {
	dir = filepath.ToSlash(strings.TrimSpace(dir))
	name = path.Base(name)
	if name == "" || name == "." {
		return dir
	}
	if dir == "" || dir == "." {
		return name
	}
	if dir == "/" {
		return "/" + name
	}
	return path.Join(strings.TrimSuffix(dir, "/"), name)
}

func cleanRemotePath(p string) string {
	p = filepath.ToSlash(strings.TrimSpace(p))
	if p == "" {
		return "."
	}
	return path.Clean(p)
}

func sameRemotePath(a, b string) bool {
	return cleanRemotePath(a) == cleanRemotePath(b)
}

func remotePathContains(parent, child string) bool {
	parent = cleanRemotePath(parent)
	child = cleanRemotePath(child)
	if parent == "." || parent == "" {
		return false
	}
	if parent == child {
		return true
	}
	if parent == "/" {
		return strings.HasPrefix(child, "/")
	}
	return strings.HasPrefix(child, parent+"/")
}

func isRemoteNotExistError(err error) bool {
	if err == nil {
		return false
	}
	if os.IsNotExist(err) {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "not exist") ||
		strings.Contains(msg, "no such file") ||
		strings.Contains(msg, "not found")
}

// GetUploadProgress handles GET /api/sftp/upload-progress/:uploadId
func (h *SftpHandler) GetUploadProgress(c *gin.Context) {
	uploadID := c.Param("uploadId")
	if data, ok := uploadProgressMap.Load(uploadID); ok {
		utils.SuccessResponse(c, http.StatusOK, data)
		return
	}
	// If not found, it might be completed or invalid
	utils.SuccessResponse(c, http.StatusOK, gin.H{"status": "not_found"})
}

func scheduleUploadProgressDelete(uploadID string) {
	if uploadID == "" {
		return
	}
	time.AfterFunc(5*time.Minute, func() {
		uploadProgressMap.Delete(uploadID)
	})
}

const (
	sftpMaxPacketSize       = 32 * 1024       // 32 KiB is the broadly supported SFTP packet size.
	sftpTransferConcurrency = 64              // Match pkg/sftp's default and make RTT less visible.
	sftpCopyBufferSize      = 4 * 1024 * 1024 // 4 MiB relay copy buffer
)

// uploadProgressReader wraps an io.Reader and reports upload progress while pkg/sftp
// pipelines writes to the remote server.
type uploadProgressReader struct {
	src        io.Reader
	written    int64
	total      int64
	onProgress func(written, total int64)
	lastReport time.Time
	ctx        interface{ Done() <-chan struct{} } // context for cancellation
}

func (pr *uploadProgressReader) Read(p []byte) (int, error) {
	if pr.ctx != nil {
		select {
		case <-pr.ctx.Done():
			return 0, fmt.Errorf("client disconnected")
		default:
		}
	}

	n, err := pr.src.Read(p)
	if n > 0 {
		pr.written += int64(n)
		if pr.onProgress != nil && time.Since(pr.lastReport) >= 200*time.Millisecond {
			pr.onProgress(pr.written, pr.total)
			pr.lastReport = time.Now()
		}
	}
	return n, err
}

// Upload handles POST /api/sftp/upload/:hostId
// Uses NDJSON streaming to report real SFTP write progress to the client.
func (h *SftpHandler) Upload(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, h.config.Server.MaxUploadSize)

	contentType := c.GetHeader("Content-Type")
	if contentType == "" || !strings.HasPrefix(contentType, "multipart/form-data") {
		utils.ErrorResponse(c, http.StatusBadRequest, "Content-Type must be multipart/form-data")
		return
	}

	// Parse boundary from Content-Type without buffering the whole body
	boundary := ""
	for _, param := range strings.Split(contentType, ";") {
		param = strings.TrimSpace(param)
		if strings.HasPrefix(param, "boundary=") {
			boundary = strings.TrimPrefix(param, "boundary=")
			boundary = strings.Trim(boundary, `"`)
			break
		}
	}
	if boundary == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "missing multipart boundary")
		return
	}

	// Use multipart.Reader for streaming – avoids writing to temp files
	mr := multipart.NewReader(c.Request.Body, boundary)

	var remotePath string
	var filename string
	var fileSize int64
	var uploadID string
	var filePart *multipart.Part

	// Read parts sequentially; expect "path", "file_size", "upload_id" and "file" fields
	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			utils.ErrorResponse(c, http.StatusBadRequest, "failed to parse multipart: "+err.Error())
			return
		}

		fieldName := part.FormName()
		if fieldName == "path" {
			data, _ := io.ReadAll(part)
			remotePath = string(data)
			part.Close()
		} else if fieldName == "file_size" {
			data, _ := io.ReadAll(part)
			fileSize, _ = strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
			part.Close()
		} else if fieldName == "upload_id" {
			data, _ := io.ReadAll(part)
			uploadID = strings.TrimSpace(string(data))
			part.Close()
			if uploadID != "" {
				uploadProgressMap.Store(uploadID, UploadProgressData{
					Percent: 0,
					Written: 0,
					Total:   fileSize,
					Speed:   "0 KB/s",
				})
			}
		} else if fieldName == "file" {
			filename = part.FileName()
			filePart = part
			break // Stop reading more parts; we'll stream the file body below
		} else {
			part.Close()
		}
	}

	if remotePath == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "path is required")
		return
	}
	if filePart == nil || filename == "" {
		utils.ErrorResponse(c, http.StatusBadRequest, "file is required")
		return
	}
	defer filePart.Close()

	// Sanitize filename to prevent path traversal
	cleanFilename := filepath.Base(filename)

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	fullPath := joinRemotePath(remotePath, cleanFilename)

	dst, err := sftpClient.Create(fullPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create remote file: "+err.Error())
		return
	}
	defer dst.Close()

	// Use actual file size from frontend for accurate progress calculation
	// Fall back to Content-Length if not provided
	totalSize := fileSize
	if totalSize <= 0 {
		totalSize = c.Request.ContentLength
	}

	startTime := time.Now()

	// Initialize progress
	if uploadID != "" {
		uploadProgressMap.Store(uploadID, UploadProgressData{
			Percent: 0,
			Written: 0,
			Total:   totalSize,
			Speed:   "0 KB/s",
		})
	}

	// Create progress reader that wraps the browser upload stream. The SFTP
	// destination then writes with concurrency instead of one packet per RTT.
	pr := &uploadProgressReader{
		src:   filePart,
		total: totalSize,
		ctx:   c.Request.Context(),
		onProgress: func(written, total int64) {
			if uploadID == "" {
				return
			}
			elapsed := time.Since(startTime).Seconds()
			speed := float64(0)
			if elapsed > 0 {
				speed = float64(written) / elapsed
			}
			percent := 0
			if total > 0 {
				percent = int(float64(written) * 100 / float64(total))
				if percent > 99 {
					percent = 99
				}
			}

			speedStr := ""
			if speed > 1024*1024 {
				speedStr = fmt.Sprintf("%.2f MB/s", speed/(1024*1024))
			} else {
				speedStr = fmt.Sprintf("%.2f KB/s", speed/1024)
			}

			uploadProgressMap.Store(uploadID, UploadProgressData{
				Percent: percent,
				Written: written,
				Total:   total,
				Speed:   speedStr,
			})
		},
	}

	if _, err := dst.ReadFromWithConcurrency(pr, sftpTransferConcurrency); err != nil {
		dst.Close()
		_ = sftpClient.Remove(fullPath)
		uploadProgressMap.Delete(uploadID)
		h.logAudit(userID, hostID, "upload", fullPath, "", c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy file: "+err.Error())
		return
	}
	if err := c.Request.Context().Err(); err != nil {
		dst.Close()
		_ = sftpClient.Remove(fullPath)
		uploadProgressMap.Delete(uploadID)
		h.logAudit(userID, hostID, "upload", fullPath, "", c.ClientIP(), err)
		utils.ErrorResponse(c, 499, "upload cancelled")
		return
	}
	if uploadID != "" {
		uploadProgressMap.Store(uploadID, UploadProgressData{
			Percent: 100,
			Written: pr.written,
			Total:   totalSize,
			Speed:   "",
		})
		scheduleUploadProgressDelete(uploadID)
	}

	h.logAudit(userID, hostID, "upload", fullPath, "", c.ClientIP(), nil)
	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"path":    fullPath,
		"written": pr.written,
	})
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
		Source       string `json:"source" binding:"required"`
		Dest         string `json:"dest" binding:"required"`
		Type         string `json:"type" binding:"required,oneof=cut copy"` // cut or copy
		DestFileName string `json:"dest_file_name"`
		Overwrite    bool   `json:"overwrite"`
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

	sourcePath, err := resolveSftpPath(sftpClient, req.Source)
	if err != nil {
		h.logAudit(userID, hostID, req.Type, req.Source, req.Dest, c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to resolve source: "+err.Error())
		return
	}
	destDir, err := resolveSftpPath(sftpClient, req.Dest)
	if err != nil {
		h.logAudit(userID, hostID, req.Type, req.Source, req.Dest, c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to resolve destination: "+err.Error())
		return
	}

	sourceStat, err := sftpClient.Stat(sourcePath)
	if err != nil {
		h.logAudit(userID, hostID, req.Type, sourcePath, destDir, c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to stat source: "+err.Error())
		return
	}

	fileName := path.Base(sourcePath)
	if strings.TrimSpace(req.DestFileName) != "" {
		fileName = path.Base(req.DestFileName)
	}
	newPath := joinRemotePath(destDir, fileName)

	if sameRemotePath(sourcePath, newPath) {
		utils.ErrorResponse(c, http.StatusBadRequest, "cannot paste into same location")
		return
	}
	if sourceStat.IsDir() && remotePathContains(sourcePath, newPath) {
		utils.ErrorResponse(c, http.StatusBadRequest, "cannot paste a directory into itself")
		return
	}

	targetExists := false
	if _, err := sftpClient.Stat(newPath); err == nil {
		targetExists = true
	} else if !isRemoteNotExistError(err) {
		h.logAudit(userID, hostID, req.Type, sourcePath, newPath, c.ClientIP(), err)
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to stat destination: "+err.Error())
		return
	}
	if targetExists {
		if !req.Overwrite {
			utils.ErrorResponse(c, http.StatusConflict, "destination already exists")
			return
		}
		if remotePathContains(newPath, sourcePath) {
			utils.ErrorResponse(c, http.StatusBadRequest, "cannot overwrite a destination that contains the source")
			return
		}
		if err := h.deleteRecursive(sftpClient, newPath); err != nil {
			h.logAudit(userID, hostID, "overwrite", newPath, "", c.ClientIP(), err)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to overwrite destination: "+err.Error())
			return
		}
	}

	if req.Type == "cut" {
		// Move is simple rename
		if err := sftpClient.Rename(sourcePath, newPath); err != nil {
			h.logAudit(userID, hostID, "move", sourcePath, newPath, c.ClientIP(), err)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to move: "+err.Error())
			return
		}
		h.logAudit(userID, hostID, "move", sourcePath, newPath, c.ClientIP(), nil)
	} else {
		// Copy is recursive
		if err := h.copyRecursive(sftpClient, sourcePath, newPath); err != nil {
			h.logAudit(userID, hostID, "copy", sourcePath, newPath, c.ClientIP(), err)
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy: "+err.Error())
			return
		}
		h.logAudit(userID, hostID, "copy", sourcePath, newPath, c.ClientIP(), nil)
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

type sftpPathSizeResult struct {
	Size   int64  `json:"size"`
	Method string `json:"method"`
	Error  string `json:"error,omitempty"`
}

func (h *SftpHandler) getRemotePathSize(ctx context.Context, sftpClient *sftp.Client, sshClient *ssh.SSHClient, targetPath string) (int64, string, error) {
	if strings.TrimSpace(targetPath) == "" {
		return 0, "", fmt.Errorf("path is required")
	}

	session, err := sshClient.GetRawClient().NewSession()
	if err == nil {
		escapedPath := utils.ShellEscape(targetPath)
		output, outputErr := session.Output("du -sk " + escapedPath)
		session.Close()
		if outputErr == nil {
			fields := strings.Fields(string(output))
			if len(fields) > 0 {
				var sizeKB int64
				if _, err := fmt.Sscanf(fields[0], "%d", &sizeKB); err == nil {
					return sizeKB * 1024, "du", nil
				}
			}
		}
	}

	var size int64
	walker := sftpClient.Walk(targetPath)
	for walker.Step() {
		select {
		case <-ctx.Done():
			return 0, "", ctx.Err()
		default:
		}
		if err := walker.Err(); err != nil {
			continue
		}
		if !walker.Stat().IsDir() {
			size += walker.Stat().Size()
		}
	}
	return size, "scan", nil
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

	size, method, err := h.getRemotePathSize(c.Request.Context(), sftpClient, sshClient, targetPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to get size: "+err.Error())
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"size":   size,
		"method": method,
	})
}

// GetDirSizes handles POST /api/sftp/sizes/:hostId for batch directory-size lookups.
func (h *SftpHandler) GetDirSizes(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID := c.Param("hostId")

	var req struct {
		Paths []string `json:"paths" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}
	if len(req.Paths) == 0 {
		utils.ErrorResponse(c, http.StatusBadRequest, "paths are required")
		return
	}
	if len(req.Paths) > 200 {
		utils.ErrorResponse(c, http.StatusBadRequest, "too many paths")
		return
	}

	sftpClient, sshClient, err := h.getSftpClient(userID, hostID)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, err.Error())
		return
	}
	defer sftpClient.Close()
	defer sshClient.Close()

	results := make(map[string]sftpPathSizeResult, len(req.Paths))
	for _, p := range req.Paths {
		p = strings.TrimSpace(p)
		if p == "" {
			results[p] = sftpPathSizeResult{Size: -1, Method: "error", Error: "path is required"}
			continue
		}
		size, method, err := h.getRemotePathSize(c.Request.Context(), sftpClient, sshClient, p)
		if err != nil {
			results[p] = sftpPathSizeResult{Size: -1, Method: "error", Error: err.Error()}
			continue
		}
		results[p] = sftpPathSizeResult{Size: size, Method: method}
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"sizes": results})
}

// sendTransferEvent writes a JSON event line and flushes for streaming
func sendTransferEvent(c *gin.Context, data map[string]interface{}) {
	var mu *sync.Mutex
	if val, exists := c.Get("transfer_mu"); exists {
		if m, ok := val.(*sync.Mutex); ok {
			mu = m
		}
	}
	if mu != nil {
		mu.Lock()
		defer mu.Unlock()
	}

	jsonBytes, _ := json.Marshal(data)
	c.Writer.Write(jsonBytes)
	c.Writer.Write([]byte("\n"))
	c.Writer.(http.Flusher).Flush()
}

// Transfer handles POST /api/sftp/transfer
// Preferred: direct rsync from source VPS to dest VPS (data bypasses this server)
// Fallback: server-side SFTP relay when rsync/auth is unavailable on the source host
func (h *SftpHandler) Transfer(c *gin.Context) {
	c.Set("transfer_mu", &sync.Mutex{})
	userID := middleware.GetUserID(c)

	var req struct {
		SourceHostID string `json:"source_host_id" binding:"required"`
		DestHostID   string `json:"dest_host_id" binding:"required"`
		SourcePath   string `json:"source_path" binding:"required"`
		DestPath     string `json:"dest_path" binding:"required"`
		DestFileName string `json:"dest_file_name"`                          // optional: rename on destination (keep-both)
		Type         string `json:"type" binding:"omitempty,oneof=cut copy"` // cut or copy
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, err.Error())
		return
	}

	var srcHost, dstHost models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", req.SourceHostID, userID).First(&srcHost).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "source host not found")
		return
	}
	if err := h.db.Where("id = ? AND user_id = ?", req.DestHostID, userID).First(&dstHost).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "destination host not found")
		return
	}
	srcPassword, srcPrivateKey := decryptHostCredentials(&srcHost, h.config.Security.EncryptionKey)
	dstPassword, dstPrivateKey := decryptHostCredentials(&dstHost, h.config.Security.EncryptionKey)

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

	resolvedSrc, err := resolveSftpPath(srcSftp, req.SourcePath)
	if err != nil {
		srcSftp.Close()
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to resolve source path: " + err.Error()})
		return
	}

	srcStat, err := srcSftp.Stat(resolvedSrc)
	if err != nil {
		srcSftp.Close()
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "source path not found: " + err.Error()})
		return
	}
	isDir := srcStat.IsDir()
	totalSize := srcStat.Size()
	if isDir {
		totalSize = 0
		walker := srcSftp.Walk(resolvedSrc)
		for walker.Step() {
			if walker.Err() == nil && !walker.Stat().IsDir() {
				totalSize += walker.Stat().Size()
			}
		}
	}
	srcSftp.Close()

	dstSftp, dstSSH, err := h.getSftpClient(userID, req.DestHostID)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to connect to destination: " + err.Error()})
		return
	}
	resolvedDest, err := resolveSftpPath(dstSftp, req.DestPath)
	isDstDir := false
	if err == nil {
		if dstStat, errStat := dstSftp.Stat(resolvedDest); errStat == nil {
			isDstDir = dstStat.IsDir()
		} else if strings.HasSuffix(req.DestPath, "/") {
			isDstDir = true
		}
	}
	dstSftp.Close()
	dstSSH.Close()
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to resolve destination path: " + err.Error()})
		return
	}

	destFileName := strings.TrimSpace(req.DestFileName)
	fileName := path.Base(resolvedSrc)
	if destFileName != "" {
		fileName = path.Base(destFileName)
	}
	sendTransferEvent(c, map[string]interface{}{
		"type": "start", "total_size": totalSize, "is_dir": isDir, "file_name": fileName,
	})

	// Direct rsync lands as the source basename when dest is a directory; use relay for rename (keep-both).
	targetFileName := fileName
	if destFileName != "" {
		targetFileName = path.Base(destFileName)
	} else if !isDstDir {
		targetFileName = path.Base(resolvedDest)
	}
	needsRename := targetFileName != path.Base(resolvedSrc)
	transferErr := executeRemoteTransfer(needsRename, remoteTransferAdapters{
		directRsync: func() bool {
			_, success := h.tryDirectRsync(c, srcSSH, dstHost, dstPassword, dstPrivateKey, resolvedSrc, resolvedDest, "", isDir, isDstDir)
			return success
		},
		serverSCP: func() bool {
			_, success := h.tryServerSCP3(c, userID, srcHost, dstHost, srcPassword, srcPrivateKey, dstPassword, dstPrivateKey, resolvedSrc, resolvedDest, "", isDir, isDstDir, totalSize)
			return success
		},
		relay: func() error {
			return h.transferViaRelay(c, userID, req.SourceHostID, req.DestHostID, resolvedSrc, resolvedDest, destFileName, totalSize)
		},
	})

	// If cut requested and transfer succeeded, delete source
	if req.Type == "cut" && transferErr == nil {
		if err := deleteRemotePathViaSSH(srcSSH, resolvedSrc); err != nil {
			sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "transfer ok but failed to remove source: " + err.Error()})
		}
	}
}

// scpDestPath builds the remote path suffix for direct host-to-host transfers (rsync/scp-style).
func scpDestPath(destPath, destFileName string, isDir, destIsDir bool) string {
	if destFileName != "" {
		target := joinRemotePath(destPath, destFileName)
		if isDir {
			return target + "/"
		}
		return target
	}
	dest := filepath.ToSlash(strings.TrimSpace(destPath))
	if dest == "" {
		dest = "."
	}
	if destIsDir {
		return strings.TrimSuffix(dest, "/") + "/"
	}
	return dest
}

// transferViaRelay uses server-side SFTP relay with progress streaming
func (h *SftpHandler) transferViaRelay(c *gin.Context, userID uint, srcHostID, dstHostID, sourcePath, destPath, destFileName string, totalSize int64) error {
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

	resolvedSrc, err := resolveSftpPath(srcSftp, sourcePath)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to resolve source path: " + err.Error()})
		return err
	}

	srcStat, err := srcSftp.Stat(resolvedSrc)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "source not found: " + err.Error()})
		return err
	}

	resolvedDest, err := resolveSftpPath(dstSftp, destPath)
	if err != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "failed to resolve destination path: " + err.Error()})
		return err
	}

	isDstDir := false
	if dstStat, errStat := dstSftp.Stat(resolvedDest); errStat == nil {
		isDstDir = dstStat.IsDir()
	} else if strings.HasSuffix(destPath, "/") {
		isDstDir = true
	}

	destFullPath := resolvedDest
	if isDstDir {
		fileName := path.Base(resolvedSrc)
		if destFileName != "" {
			fileName = path.Base(destFileName)
		}
		destFullPath = joinRemotePath(resolvedDest, fileName)
	}

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
					"type":        "progress",
					"percent":     pct,
					"speed":       speedStr,
					"transferred": transferred,
					"total":       totalSize,
				})
			}
		}
	}

	var transferErr error
	isRename := path.Base(destFullPath) != path.Base(resolvedSrc)
	if !isRename && isDstDir {
		// Try Tar stream relay first (fastest)
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "using Tar stream relay (high performance)"})
		transferErr = h.tryTarRelay(c.Request.Context(), srcSSH, dstSSH, resolvedSrc, resolvedDest, onProgress)
		if transferErr != nil {
			sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "Tar stream failed, falling back to SFTP relay: " + transferErr.Error()})
			// Fallback to SFTP if Tar fails
			if srcStat.IsDir() {
				transferErr = h.relayRecursive(c.Request.Context(), srcSftp, dstSftp, resolvedSrc, destFullPath, onProgress)
			} else {
				transferErr = h.relaySingleFile(c.Request.Context(), srcSftp, dstSftp, resolvedSrc, destFullPath, onProgress)
			}
		}
	} else {
		sendTransferEvent(c, map[string]interface{}{"type": "info", "message": "using SFTP relay (renaming)"})
		if srcStat.IsDir() {
			transferErr = h.relayRecursive(c.Request.Context(), srcSftp, dstSftp, resolvedSrc, destFullPath, onProgress)
		} else {
			transferErr = h.relaySingleFile(c.Request.Context(), srcSftp, dstSftp, resolvedSrc, destFullPath, onProgress)
		}
	}

	if transferErr != nil {
		sendTransferEvent(c, map[string]interface{}{"type": "error", "message": "relay: " + transferErr.Error()})
		return transferErr
	}
	sendTransferEvent(c, map[string]interface{}{
		"type": "complete", "method": "relay", "dest_path": destFullPath,
	})
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

func (h *SftpHandler) relaySingleFile(ctx context.Context, src, dst *sftp.Client, srcPath, dstPath string, onProgress func(int64)) error {
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

	buf := make([]byte, sftpCopyBufferSize)
	totalWritten := int64(0)

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
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

func (h *SftpHandler) relayRecursive(ctx context.Context, src, dst *sftp.Client, srcPath, dstPath string, onProgress func(int64)) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}
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
			s := path.Join(srcPath, entry.Name())
			d := path.Join(dstPath, entry.Name())
			if err := h.relayRecursive(ctx, src, dst, s, d, onProgress); err != nil {
				return err
			}
		}
	} else {
		// Retry logic for single file transfer
		maxRetries := 3
		var lastErr error
		for attempt := 0; attempt < maxRetries; attempt++ {
			var fileTransferred int64
			fileOnProgress := func(n int64) {
				fileTransferred += n
				if onProgress != nil {
					onProgress(n)
				}
			}
			lastErr = h.relaySingleFile(ctx, src, dst, srcPath, dstPath, fileOnProgress)
			if lastErr == nil {
				return nil
			}
			if onProgress != nil {
				onProgress(-fileTransferred)
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

type progressReader struct {
	r          io.Reader
	onProgress func(int64)
}

func (pr *progressReader) Read(p []byte) (int, error) {
	n, err := pr.r.Read(p)
	if n > 0 && pr.onProgress != nil {
		pr.onProgress(int64(n))
	}
	return n, err
}

func (h *SftpHandler) tryTarRelay(ctx context.Context, srcSSH, dstSSH *ssh.SSHClient, resolvedSrc, resolvedDest string, onProgress func(int64)) error {
	srcSession, err := srcSSH.GetRawClient().NewSession()
	if err != nil {
		return err
	}
	defer srcSession.Close()

	dstSession, err := dstSSH.GetRawClient().NewSession()
	if err != nil {
		return err
	}
	defer dstSession.Close()

	doneChan := make(chan struct{})
	defer close(doneChan)

	go func() {
		select {
		case <-ctx.Done():
			srcSession.Close()
			dstSession.Close()
		case <-doneChan:
		}
	}()

	srcStdout, err := srcSession.StdoutPipe()
	if err != nil {
		return err
	}

	dstStdin, err := dstSession.StdinPipe()
	if err != nil {
		return err
	}

	var srcStderr, dstStderr bytes.Buffer
	srcSession.Stderr = &srcStderr
	dstSession.Stderr = &dstStderr

	// Start destination tar extract
	dstCmd := fmt.Sprintf("tar -xf - -C %s", utils.ShellEscape(resolvedDest))
	if err := dstSession.Start(dstCmd); err != nil {
		return fmt.Errorf("failed to start dest tar: %w", err)
	}

	// Start source tar create
	srcDir := filepath.ToSlash(filepath.Dir(resolvedSrc))
	srcBase := filepath.Base(resolvedSrc)
	srcCmd := fmt.Sprintf("tar -cf - -C %s %s", utils.ShellEscape(srcDir), utils.ShellEscape(srcBase))
	if err := srcSession.Start(srcCmd); err != nil {
		dstStdin.Close()
		return fmt.Errorf("failed to start source tar: %w", err)
	}

	// Copy data with progress
	pr := &progressReader{
		r:          srcStdout,
		onProgress: onProgress,
	}

	// Use a 4MB buffer (sftpCopyBufferSize) to significantly reduce CPU context switches on very large files
	buf := make([]byte, sftpCopyBufferSize)
	_, copyErr := io.CopyBuffer(dstStdin, pr, buf)

	// Close dstStdin so dstSession knows EOF
	dstStdin.Close()

	srcWaitErr := srcSession.Wait()
	dstWaitErr := dstSession.Wait()

	if copyErr != nil {
		return fmt.Errorf("stream error: %w", copyErr)
	}
	if srcWaitErr != nil {
		return fmt.Errorf("source tar failed: %w, stderr: %s", srcWaitErr, srcStderr.String())
	}
	if dstWaitErr != nil {
		return fmt.Errorf("dest tar failed: %w, stderr: %s", dstWaitErr, dstStderr.String())
	}

	return nil
}
