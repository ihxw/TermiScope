package utils

import (
	"log" // Added for potential future use, though not directly used by SafeErrorResponse in this snippet
	"strconv"

	"github.com/gin-gonic/gin"
)

// SuccessResponse creates a success JSON response
func SuccessResponse(c *gin.Context, statusCode int, data interface{}) {
	c.JSON(statusCode, gin.H{
		"success": true,
		"data":    data,
	})
}

// ErrorResponse creates an error JSON response
func ErrorResponse(c *gin.Context, statusCode int, message string) {
	c.JSON(statusCode, gin.H{
		"success": false,
		"error":   message,
	})
}

// SafeErrorResponse logs the detailed error but returns a safe generic message to the client
// Use this for errors that might expose sensitive system information
func SafeErrorResponse(c *gin.Context, statusCode int, detailedError error, genericMessage string) {
	// Log the detailed error for debugging
	// Assuming LogError is a custom logging function, replacing with log.Printf for compilation
	log.Printf("Error occurred: %v | Request: %s %s | Client: %s",
		detailedError,
		c.Request.Method,
		c.Request.URL.Path,
		c.ClientIP())

	// Return generic message to client
	c.JSON(statusCode, gin.H{
		"success": false,
		"error":   genericMessage,
	})
}

// PaginatedResponse creates a paginated JSON response
func PaginatedResponse(c *gin.Context, statusCode int, data interface{}, total int64, page, pageSize int) {
	c.JSON(statusCode, gin.H{
		"success": true,
		"data":    data,
		"pagination": gin.H{
			"total":     total,
			"page":      page,
			"page_size": pageSize,
			"pages":     (total + int64(pageSize) - 1) / int64(pageSize),
		},
	})
}

// GetIntQuery retrieves a query parameter as an integer or returns a default value
func GetIntQuery(c *gin.Context, key string, defaultValue int) int {
	valStr := c.Query(key)
	if valStr == "" {
		return defaultValue
	}

	val, err := strconv.Atoi(valStr)
	if err != nil {
		return defaultValue
	}
	return val
}
