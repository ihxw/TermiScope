package models

import (
	"encoding/json"
	"log"
	"time"

	"gorm.io/gorm"
)

// SecurityEventType defines types of security events
type SecurityEventType string

const (
	LoginFailed          SecurityEventType = "LOGIN_FAILED"
	LoginSuccess         SecurityEventType = "LOGIN_SUCCESS"
	Logout               SecurityEventType = "LOGOUT"
	TokenRevoked         SecurityEventType = "TOKEN_REVOKED"
	PermissionDenied     SecurityEventType = "PERMISSION_DENIED"
	PasswordChanged      SecurityEventType = "PASSWORD_CHANGED"
	TwoFAEnabled         SecurityEventType = "2FA_ENABLED"
	TwoFADisabled        SecurityEventType = "2FA_DISABLED"
	SSHHostKeyMismatch   SecurityEventType = "SSH_HOST_KEY_MISMATCH"
	BruteForceDetected   SecurityEventType = "BRUTE_FORCE_DETECTED"
	SuspiciousActivity   SecurityEventType = "SUSPICIOUS_ACTIVITY"
	DataExport           SecurityEventType = "DATA_EXPORT"
	ConfigChanged        SecurityEventType = "CONFIG_CHANGED"
	CommandInjection     SecurityEventType = "COMMAND_INJECTION_ATTEMPT"
)

// SecurityEventSeverity defines severity levels
type SecurityEventSeverity string

const (
	SeverityLow      SecurityEventSeverity = "LOW"
	SeverityMedium   SecurityEventSeverity = "MEDIUM"
	SeverityHigh     SecurityEventSeverity = "HIGH"
	SeverityCritical SecurityEventSeverity = "CRITICAL"
)

// SecurityEvent represents a security-related event
type SecurityEvent struct {
	ID        uint                  `gorm:"primaryKey" json:"id"`
	UserID    uint                  `gorm:"index" json:"user_id"`
	Username  string                `gorm:"size:100" json:"username"`
	EventType SecurityEventType     `gorm:"size:50;not null;index" json:"event_type"`
	Severity  SecurityEventSeverity `gorm:"size:20;not null" json:"severity"`
	IPAddress string                `gorm:"size:45" json:"ip_address"` // IPv6
	UserAgent string                `gorm:"type:text" json:"user_agent"`
	Details   string                `gorm:"type:text" json:"details"`
	Metadata  string                `gorm:"type:text" json:"metadata"` // JSON
	CreatedAt time.Time             `gorm:"index" json:"created_at"`
}

// SecurityEventLog records a security event
func SecurityEventLog(db *gorm.DB, eventType SecurityEventType, severity SecurityEventSeverity,
	userID uint, username, ipAddress, userAgent, details string, metadata map[string]interface{}) {

	// 序列化元数据
	var metadataJSON string
	if metadata != nil {
		data, _ := json.Marshal(metadata)
		metadataJSON = string(data)
	}

	event := SecurityEvent{
		UserID:    userID,
		Username:  username,
		EventType: eventType,
		Severity:  severity,
		IPAddress: ipAddress,
		UserAgent: userAgent,
		Details:   details,
		Metadata:  metadataJSON,
		CreatedAt: time.Now(),
	}

	db.Create(&event)

	// 高风险事件触发告警
	if severity == SeverityHigh || severity == SeverityCritical {
		go SendSecurityAlert(event)
	}
}

// SendSecurityAlert sends alerts for high-severity events
func SendSecurityAlert(event SecurityEvent) {
	// 实现告警逻辑（邮件、Telegram、Webhook 等）
	// 这里可以根据系统配置发送不同类型的告警
	log.Printf("🚨 安全告警 [%s]: %s - 用户：%s, IP: %s, 详情：%s",
		event.Severity, event.EventType, event.Username, event.IPAddress, event.Details)
}

// CheckBruteForce checks for brute force attempts
func CheckBruteForce(db *gorm.DB, ipAddress string, window time.Duration, threshold int) bool {
	var count int64
	since := time.Now().Add(-window)

	db.Model(&SecurityEvent{}).
		Where("ip_address = ? AND event_type = ? AND created_at >= ?",
			ipAddress, LoginFailed, since).
		Count(&count)

	return count >= int64(threshold)
}

// GetUserSecurityEvents retrieves security events for a user
func GetUserSecurityEvents(db *gorm.DB, userID uint, limit int) []SecurityEvent {
	var events []SecurityEvent
	db.Where("user_id = ?", userID).
		Order("created_at DESC").
		Limit(limit).
		Find(&events)
	return events
}

// GetRecentSecurityEvents retrieves recent security events with optional filtering
func GetRecentSecurityEvents(db *gorm.DB, eventType SecurityEventType, severity SecurityEventSeverity, limit int) []SecurityEvent {
	var events []SecurityEvent
	query := db.Model(&SecurityEvent{})

	if eventType != "" {
		query = query.Where("event_type = ?", eventType)
	}

	if severity != "" {
		query = query.Where("severity = ?", severity)
	}

	query.Order("created_at DESC").Limit(limit).Find(&events)
	return events
}
