package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type CommandTemplateHandler struct {
	db *gorm.DB
}

func NewCommandTemplateHandler(db *gorm.DB) *CommandTemplateHandler {
	return &CommandTemplateHandler{
		db: db,
	}
}

type CreateCommandTemplateRequest struct {
	Name        string `json:"name" binding:"required"`
	Command     string `json:"command" binding:"required"`
	Description string `json:"description"`
}

// List returns all command templates for the current user
func (h *CommandTemplateHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var templates []models.CommandTemplate
	if err := h.db.Where("user_id = ?", userID).Find(&templates).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch templates")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, templates)
}

// Create creates a new command template
func (h *CommandTemplateHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req CreateCommandTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	template := &models.CommandTemplate{
		UserID:      userID,
		Name:        req.Name,
		Command:     req.Command,
		Description: req.Description,
	}

	if err := h.db.Create(template).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create template")
		return
	}

	utils.SuccessResponse(c, http.StatusCreated, template)
}

// Update updates an existing command template
func (h *CommandTemplateHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req CreateCommandTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var template models.CommandTemplate
	if err := h.db.Where("id = ? AND user_id = ?", id, userID).First(&template).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "template not found")
		return
	}

	template.Name = req.Name
	template.Command = req.Command
	template.Description = req.Description

	if err := h.db.Save(&template).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update template")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, template)
}

// Delete deletes a command template
func (h *CommandTemplateHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	result := h.db.Where("id = ? AND user_id = ?", id, userID).Delete(&models.CommandTemplate{})
	if result.Error != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete template")
		return
	}
	if result.RowsAffected == 0 {
		utils.ErrorResponse(c, http.StatusNotFound, "template not found")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{"message": "template deleted successfully"})
}
