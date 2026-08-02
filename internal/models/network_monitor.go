package models

import (
	"time"
)

// NetworkMonitorTask represents a configuration for ping/tcping monitoring
type NetworkMonitorTask struct {
	ID         uint      `json:"id" gorm:"primaryKey"`
	HostID     uint      `json:"host_id" gorm:"index;not null"`
	TemplateID uint      `json:"template_id" gorm:"index;default:0"` // 0 = manual, >0 = from template
	Type       string    `json:"type" gorm:"size:10;not null"`       // ping, tcping
	Target     string    `json:"target" gorm:"size:255;not null"`
	Port       int       `json:"port"` // Only for tcping
	Label      string    `json:"label" gorm:"size:100"`
	Frequency  int       `json:"frequency" gorm:"default:60"` // Seconds
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// NetworkMonitorResult represents a single check result
type NetworkMonitorResult struct {
	ID         uint      `json:"id" gorm:"primaryKey"`
	TaskID     uint      `json:"task_id" gorm:"index;not null"`
	Latency    float64   `json:"latency"`     // ms
	PacketLoss float64   `json:"packet_loss"` // Percentage (0-100)
	Success    bool      `json:"success"`
	CreatedAt  time.Time `json:"created_at" gorm:"index"` // Indexed for cleanup
}
