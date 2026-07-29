package models

import (
	"time"

	"gorm.io/gorm"
)

type ConnectionLog struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	SSHHostID      *uint          `gorm:"index" json:"ssh_host_id"`
	Host           string         `gorm:"size:255;not null" json:"host"`
	Port           int            `gorm:"not null" json:"port"`
	Username       string         `gorm:"size:100;not null" json:"username"`
	Status         string         `gorm:"size:20;not null" json:"status"` // success, failed, disconnected
	ErrorMessage   string         `gorm:"type:text" json:"error_message,omitempty"`
	ConnectedAt    time.Time      `gorm:"not null" json:"connected_at"`
	DisconnectedAt *time.Time     `json:"disconnected_at,omitempty"`
	Duration       int            `json:"duration"` // in seconds
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	User    User     `gorm:"foreignKey:UserID" json:"user,omitempty"`
	SSHHost *SSHHost `gorm:"foreignKey:SSHHostID" json:"ssh_host,omitempty"`
}

// TableName specifies the table name
func (ConnectionLog) TableName() string {
	return "connection_logs"
}
