package models

import "time"

type NetworkMonitorTemplate struct {
	ID        uint      `gorm:"primarykey" json:"id"`
	Name      string    `json:"name"`
	Type      string    `json:"type"` // ping, tcping
	Target    string    `json:"target"`
	Port      int       `json:"port"`
	Label     string    `json:"label"`
	Frequency int       `json:"frequency"`                            // seconds
	Color     string    `json:"color" gorm:"size:20;default:#1890ff"` // Chart display color
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
