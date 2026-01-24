package models

import (
	"time"
)

type MonitorStatusLog struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	HostID    uint      `gorm:"index" json:"host_id"`
	Status    string    `gorm:"size:20;not null" json:"status"` // online, offline
	CreatedAt time.Time `json:"created_at"`
}

// TableName specifies the table name
func (MonitorStatusLog) TableName() string {
	return "monitor_status_logs"
}
