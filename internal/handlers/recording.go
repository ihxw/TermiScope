package handlers

import (
	"bufio"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type RecordingHandler struct {
	db *gorm.DB
}

func NewRecordingHandler(db *gorm.DB) *RecordingHandler {
	return &RecordingHandler{db: db}
}

// List returns a list of terminal recordings for the current user
func (h *RecordingHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	db := h.db.Model(&models.TerminalRecording{}).Where("user_id = ?", userID)
	var total int64
	db.Count(&total)

	page := utils.GetIntQuery(c, "page", 1)
	pageSize := utils.GetIntQuery(c, "page_size", 0)
	if page < 1 {
		page = 1
	}

	q := db.Order("created_at desc")
	if pageSize > 0 {
		if pageSize > 200 {
			pageSize = 200
		}
		q = q.Offset((page - 1) * pageSize).Limit(pageSize)
	}

	var recordings []models.TerminalRecording
	if err := q.Find(&recordings).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch recordings")
		return
	}

	if pageSize > 0 {
		utils.SuccessResponse(c, http.StatusOK, gin.H{
			"data":      recordings,
			"total":     total,
			"page":      page,
			"page_size": pageSize,
		})
		return
	}
	utils.SuccessResponse(c, http.StatusOK, recordings)
}

// GetStream streams the recording content (JSON lines)
func (h *RecordingHandler) GetStream(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var recording models.TerminalRecording
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&recording).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "recording not found")
		return
	}

	f, err := os.Open(recording.FilePath)
	if err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to open recording file")
		return
	}
	defer f.Close()

	c.Header("Content-Type", "application/x-asciicast")

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		c.Writer.Write(scanner.Bytes())
		c.Writer.WriteString("\n")
		c.Writer.Flush()
	}
}

// Delete removes a recording
func (h *RecordingHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var recording models.TerminalRecording
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&recording).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "recording not found")
		return
	}

	// Delete file
	os.Remove(recording.FilePath)

	// Delete record
	if err := h.db.Delete(&recording).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete recording")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "recording deleted successfully"})
}
