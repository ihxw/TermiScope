package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/ihxw/termiscope/internal/middleware"
	"github.com/ihxw/termiscope/internal/models"
	"github.com/ihxw/termiscope/internal/utils"
	"gorm.io/gorm"
)

type UserHandler struct {
	db *gorm.DB
}

func NewUserHandler(db *gorm.DB) *UserHandler {
	return &UserHandler{db: db}
}

type CreateUserRequest struct {
	Username    string `json:"username" binding:"required"`
	Password    string `json:"password" binding:"required,min=8"`
	Email       string `json:"email" binding:"required,email"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role" binding:"required,oneof=admin user"`
}

type UpdateUserRequest struct {
	Email       string `json:"email" binding:"omitempty,email"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role" binding:"omitempty,oneof=admin user"`
	Status      string `json:"status" binding:"omitempty,oneof=active disabled"`
	Password    string `json:"password" binding:"omitempty,min=8"`
}

// GetUsers returns a list of users (admin only)
func (h *UserHandler) GetUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "10"))
	search := c.Query("search")

	query := h.db.Model(&models.User{})

	// Search filter
	if search != "" {
		query = query.Where("username LIKE ? OR email LIKE ? OR display_name LIKE ?",
			"%"+search+"%", "%"+search+"%", "%"+search+"%")
	}

	// Count total
	var total int64
	query.Count(&total)

	// Paginate
	var users []models.User
	offset := (page - 1) * pageSize
	if err := query.Offset(offset).Limit(pageSize).Find(&users).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to fetch users")
		return
	}

	utils.PaginatedResponse(c, http.StatusOK, users, total, page, pageSize)
}

// CreateUser creates a new user (admin only)
func (h *UserHandler) CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	// Check if username or email already exists
	var count int64
	h.db.Model(&models.User{}).Where("username = ? OR email = ?", req.Username, req.Email).Count(&count)
	if count > 0 {
		utils.ErrorResponse(c, http.StatusConflict, "username or email already exists")
		return
	}

	// Create user
	user := &models.User{
		Username:    req.Username,
		Email:       req.Email,
		DisplayName: req.DisplayName,
		Role:        req.Role,
		Status:      "active",
	}

	if err := user.SetPassword(req.Password); err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	if err := h.db.Create(user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to create user")
		return
	}

	utils.SuccessResponse(c, http.StatusCreated, user)
}

// UpdateUser updates a user (admin only)
func (h *UserHandler) UpdateUser(c *gin.Context) {
	id := c.Param("id")

	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request: "+err.Error())
		return
	}

	var user models.User
	if err := h.db.First(&user, id).Error; err != nil {
		utils.ErrorResponse(c, http.StatusNotFound, "user not found")
		return
	}

	// Update fields
	if req.Email != "" {
		user.Email = req.Email
	}
	if req.DisplayName != "" {
		user.DisplayName = req.DisplayName
	}
	if req.Role != "" {
		user.Role = req.Role
	}
	if req.Status != "" {
		user.Status = req.Status
	}
	if req.Password != "" {
		if err := user.SetPassword(req.Password); err != nil {
			utils.ErrorResponse(c, http.StatusInternalServerError, "failed to hash password")
			return
		}
	}

	if err := h.db.Save(&user).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to update user")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, user)
}

// DeleteUser deletes a user (admin only)
func (h *UserHandler) DeleteUser(c *gin.Context) {
	id := c.Param("id")
	currentUserID := middleware.GetUserID(c)

	// Prevent self-deletion
	userID, _ := strconv.ParseUint(id, 10, 32)
	if uint(userID) == currentUserID {
		utils.ErrorResponse(c, http.StatusBadRequest, "cannot delete your own account")
		return
	}

	if err := h.db.Delete(&models.User{}, id).Error; err != nil {
		utils.ErrorResponse(c, http.StatusInternalServerError, "failed to delete user")
		return
	}

	utils.SuccessResponse(c, http.StatusOK, gin.H{
		"message": "user deleted successfully",
	})
}
