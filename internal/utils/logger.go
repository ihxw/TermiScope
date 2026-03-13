package utils

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"

	"gopkg.in/natefinch/lumberjack.v2"
)

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
		log.Printf("[ERROR] "+format, v...)
		return
	}

	msg := fmt.Sprintf(format, v...)

	// Get caller info (skip 1 frame to get caller of LogError)
	_, file, line, ok := runtime.Caller(1)
	if !ok {
		file = "unknown"
		line = 0
	}

	// Format: [2023/01/01 12:00:00] file.go:123: Error message
	ErrorLogger.Printf("%s:%d: %s", filepath.Base(file), line, msg)

	// Also print to stderr/console for dev visibility
	log.Printf("[ERROR] %s:%d: %s", filepath.Base(file), line, msg)
}
