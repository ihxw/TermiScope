package utils

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"runtime"

	"gopkg.in/natefinch/lumberjack.v2"
)

// SensitivePatterns defines regex patterns for sensitive data
var SensitivePatterns = []struct {
	Pattern     *regexp.Regexp
	Replacement string
}{
	{regexp.MustCompile(`(?i)(password|passwd|pwd)["']?\s*[:=]\s*["']?[^"'\s,}]+`), "$1=***REDACTED***"},
	{regexp.MustCompile(`(?i)(token|secret|key|api_key)["']?\s*[:=]\s*["']?[^"'\s,}]+`), "$1=***REDACTED***"},
	{regexp.MustCompile(`Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+`), "Bearer ***REDACTED***"},
	{regexp.MustCompile(`(?i)(authorization)\s*:\s*[A-Za-z0-9\-_]+`), "$1: ***REDACTED***"},
	{regexp.MustCompile(`[A-Fa-f0-9]{32}`), "***REDACTED_HEX***"}, // 匹配 32 位十六进制 (如密钥)
}

// SanitizeLog removes or masks sensitive information from log messages
func SanitizeLog(message string) string {
	sanitized := message
	
	for _, pattern := range SensitivePatterns {
		sanitized = pattern.Pattern.ReplaceAllString(sanitized, pattern.Replacement)
	}
	
	return sanitized
}

var ErrorLogger *log.Logger

// InitErrorLogger initializes the global ErrorLogger to write to the specified file
func InitErrorLogger(logPath string) {
	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(logPath), 0755); err != nil {
		log.Printf("Failed to create log directory: %v", err)
	}

	rotationLogger := &lumberjack.Logger{
		Filename:   logPath,
		MaxSize:    10, // megabytes
		MaxBackups: 5,
		MaxAge:     30, // days
		Compress:   true,
	}

	ErrorLogger = log.New(rotationLogger, "", log.LstdFlags)
}

// LogError writes an error message to the error log with caller information
func LogError(format string, v ...interface{}) {
	if ErrorLogger == nil {
		// Fallback to standard log if not initialized
		msg := fmt.Sprintf(format, v...)
		sanitizedMsg := SanitizeLog(msg)
		log.Printf("[ERROR] %s", sanitizedMsg)
		return
	}

	msg := fmt.Sprintf(format, v...)
	sanitizedMsg := SanitizeLog(msg)

	// Get caller info (skip 1 frame to get caller of LogError)
	_, file, line, ok := runtime.Caller(1)
	if !ok {
		file = "unknown"
		line = 0
	}

	// Format: [2023/01/01 12:00:00] file.go:123: Error message
	ErrorLogger.Printf("%s:%d: %s", filepath.Base(file), line, sanitizedMsg)

	// Also print to stderr/console for dev visibility
	log.Printf("[ERROR] %s:%d: %s", filepath.Base(file), line, sanitizedMsg)
}
