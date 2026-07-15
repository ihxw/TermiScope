package utils

import (
	// Added for potential future use, though not directly used by SafeErrorResponse in this snippet
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

// ErrorResponse creates an error JSON response and logs the error
func ErrorResponse(c *gin.Context, statusCode int, message string) {
	// Log the error automatically for all 5xx errors or if specifically requested (though usually we log all errors for visibility in this request)
	// Let's log all errors that are sent via this method to ensure we capture "why" a request failed.
	// We skip logging for 404s to avoid noise usually, but user asked for "all possible errors".
	// Let's log 4xx and 5xx.

	// Format: [Method] [Path] [IP] -> [Status] Message
	LogError("API Error | %-7s %s | IP: %s | Status: %d | Message: %s",
		c.Request.Method, c.Request.URL.Path, c.ClientIP(), statusCode, message)

	c.JSON(statusCode, gin.H{
		"success": false,
		"error":   message,
	})
}

// SafeErrorResponse logs the detailed error but returns a safe generic message to the client
// Use this for errors that might expose sensitive system information
func SafeErrorResponse(c *gin.Context, statusCode int, detailedError error, genericMessage string) {
	// Log the detailed error using our custom logger
	LogError("API Error | %-7s %s | IP: %s | Status: %d | Detailed: %v",
		c.Request.Method, c.Request.URL.Path, c.ClientIP(), statusCode, detailedError)

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
