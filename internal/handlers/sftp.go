package handlers

import (
	"fmt"
	"io"
	"net/http"
	"path"
	"path/filepath"
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

// getSftpClient helper to create an SFTP client for a host
func (h *SftpHandler) getSftpClient(userID uint, hostID string) (*sftp.Client, *ssh.SSHClient, error) {
	// Get SSH host from database
	var host models.SSHHost
	if err := h.db.Where("id = ? AND user_id = ?", hostID, userID).First(&host).Error; err != nil {
		return nil, nil, fmt.Errorf("host not found")
	}

	// Decrypt credentials
	var password, privateKey string
	if host.PasswordEncrypted != "" {
		decrypted, err := utils.DecryptAES(host.PasswordEncrypted, h.config.Security.EncryptionKey)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to decrypt password")
		}
		password = decrypted
	}
	if host.PrivateKeyEncrypted != "" {
		decrypted, err := utils.DecryptAES(host.PrivateKeyEncrypted, h.config.Security.EncryptionKey)
		if err != nil {
			return nil, nil, fmt.Errorf("failed to decrypt private key")
		}
		privateKey = decrypted
	}

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
		return nil, nil, fmt.Errorf("failed to connect: %w", err)
	}

	// TOFU: Save fingerprint if it was empty
	if host.Fingerprint == "" {
		newFp := sshClient.GetFingerprint()
		if newFp != "" {
			host.Fingerprint = newFp
			h.db.Save(&host)
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

	file, err := sftpClient.Open(targetPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to open file: "+err.Error())
		return
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to stat file: "+err.Error())
		return
	}

	if stat.IsDir() {
		utils.ErrorResponse(c, http.StatusBadRequest, "cannot download a directory")
		return
	}

	c.Header("Content-Disposition", "attachment; filename="+path.Base(targetPath))
	c.Header("Content-Type", "application/octet-stream")
	c.Header("Content-Length", fmt.Sprintf("%d", stat.Size()))

	io.Copy(c.Writer, file)
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

	fullPath := filepath.Join(remotePath, header.Filename)
	fullPath = filepath.ToSlash(fullPath) // Ensure forward slashes for Linux remotes

	dst, err := sftpClient.Create(fullPath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create remote file: "+err.Error())
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy file: "+err.Error())
		return
	}

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
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete: "+err.Error())
		return
	}

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
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to rename: "+err.Error())
		return
	}

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
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to move: "+err.Error())
			return
		}
	} else {
		// Copy is recursive
		if err := h.copyRecursive(sftpClient, req.Source, newPath); err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to copy: "+err.Error())
			return
		}
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
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create directory: "+err.Error())
		return
	}

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
