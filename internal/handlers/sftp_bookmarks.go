package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

const (
	sftpBookmarkTypeHistory  = "history"
	sftpBookmarkTypeFavorite = "favorite"
	sftpHistoryLimit         = 15
	sftpFavoritesLimit       = 100
)

type sftpPathBookmarksResponse struct {
	History   []string `json:"history"`
	Favorites []string `json:"favorites"`
}

type sftpPathBookmarksRequest struct {
	History   []string `json:"history"`
	Favorites []string `json:"favorites"`
}

func normalizeSftpBookmarkPaths(paths []string, limit int) []string {
	out := make([]string, 0, len(paths))
	seen := make(map[string]struct{}, len(paths))
	for _, p := range paths {
		path := strings.TrimSpace(p)
		if path == "" || path == "." {
			continue
		}
		if _, ok := seen[path]; ok {
			continue
		}
		seen[path] = struct{}{}
		out = append(out, path)
		if len(out) >= limit {
			break
		}
	}
	return out
}

func (h *SftpHandler) parseOwnedHostID(c *gin.Context) (uint, bool) {
	userID := middleware.GetUserID(c)
	hostIDParam := c.Param("hostId")
	hostID, err := strconv.ParseUint(hostIDParam, 10, 32)
	if err != nil || hostID == 0 {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid host id")
		return 0, false
	}

	var count int64
	if err := h.db.Model(&models.SSHHost{}).Where("id = ? AND user_id = ?", uint(hostID), userID).Count(&count).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to verify host")
		return 0, false
	}
	if count == 0 {
		utils.ErrorResponse(c, http.StatusNotFound, "host not found")
		return 0, false
	}
	return uint(hostID), true
}

// GetPathBookmarks returns server-side SFTP history and favorites for a host.
func (h *SftpHandler) GetPathBookmarks(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID, ok := h.parseOwnedHostID(c)
	if !ok {
		return
	}

	var rows []models.SftpPathBookmark
	if err := h.db.
		Where("user_id = ? AND host_id = ?", userID, hostID).
		Order("type ASC, position ASC, updated_at DESC").
		Find(&rows).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch SFTP bookmarks")
		return
	}

	resp := sftpPathBookmarksResponse{
		History:   []string{},
		Favorites: []string{},
	}
	for _, row := range rows {
		switch row.Type {
		case sftpBookmarkTypeHistory:
			resp.History = append(resp.History, row.Path)
		case sftpBookmarkTypeFavorite:
			resp.Favorites = append(resp.Favorites, row.Path)
		}
	}

	utils.SuccessResponse(c, http.StatusOK, resp)
}

// SavePathBookmarks replaces server-side SFTP history and favorites for a host.
func (h *SftpHandler) SavePathBookmarks(c *gin.Context) {
	userID := middleware.GetUserID(c)
	hostID, ok := h.parseOwnedHostID(c)
	if !ok {
		return
	}

	var req sftpPathBookmarksRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	history := normalizeSftpBookmarkPaths(req.History, sftpHistoryLimit)
	favorites := normalizeSftpBookmarkPaths(req.Favorites, sftpFavoritesLimit)

	if err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("user_id = ? AND host_id = ?", userID, hostID).Delete(&models.SftpPathBookmark{}).Error; err != nil {
			return err
		}

		rows := make([]models.SftpPathBookmark, 0, len(history)+len(favorites))
		for i, path := range history {
			rows = append(rows, models.SftpPathBookmark{
				UserID:   userID,
				HostID:   hostID,
				Type:     sftpBookmarkTypeHistory,
				Path:     path,
				Position: i,
			})
		}
		for i, path := range favorites {
			rows = append(rows, models.SftpPathBookmark{
				UserID:   userID,
				HostID:   hostID,
				Type:     sftpBookmarkTypeFavorite,
				Path:     path,
				Position: i,
			})
		}
		if len(rows) == 0 {
			return nil
		}
		return tx.Create(&rows).Error
	}); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to save SFTP bookmarks")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, sftpPathBookmarksResponse{
		History:   history,
		Favorites: favorites,
	})
}
