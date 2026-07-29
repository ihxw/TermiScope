package models

import "time"

// SftpAuditLog records SFTP file operations
type SftpAuditLog struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"not null;index" json:"user_id"`
	HostID     uint      `gorm:"not null;index" json:"host_id"`
	Action     string    `gorm:"size:50;not null" json:"action"`             // e.g., "upload", "download", "delete", "rename", "mkdir"
	SourcePath string    `gorm:"size:500;not null" json:"source_path"`       // E.g., remote filename or "from" in rename
	DestPath   string    `gorm:"size:500" json:"dest_path"`                  // E.g., "to" in rename or local download path indicator
	ClientIP   string    `gorm:"size:45" json:"client_ip"`                   // IP address of the client performing the action
	Status     string    `gorm:"size:20;default:'success'" json:"status"`    // "success", "failed"
	ErrorMsg   string    `gorm:"type:text" json:"error_msg"`                 // Optional error explanation
	CreatedAt  time.Time `json:"created_at"`
}

// TableName specifies the table name
func (SftpAuditLog) TableName() string {
	return "sftp_audit_logs"
}
