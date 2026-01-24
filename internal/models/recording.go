package models

import (
	"time"

	"gorm.io/gorm"
)

type TerminalRecording struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	UserID    uint           `gorm:"index;not null" json:"user_id"`
	SSHHostID uint           `gorm:"index;not null" json:"ssh_host_id"`
	Host      string         `json:"host"`
	Username  string         `json:"username"`
	FilePath  string         `gorm:"size:255;not null" json:"file_path"`
	Duration  int            `json:"duration"` // in seconds
	StartTime time.Time      `json:"start_time"`
	EndTime   *time.Time     `json:"end_time"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (TerminalRecording) TableName() string {
	return "terminal_recordings"
}
