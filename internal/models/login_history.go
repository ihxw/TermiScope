package models

import (
	"time"

	"gorm.io/gorm"
)

// LoginHistory records successful web logins
type LoginHistory struct {
	ID              uint           `gorm:"primaryKey" json:"id"`
	UserID          uint           `gorm:"index;not null" json:"user_id"`
	Username        string         `gorm:"size:50;not null" json:"username"`
	IPAddress       string         `gorm:"size:45" json:"ip_address"`
	UserAgent       string         `gorm:"size:255" json:"user_agent"`
	JTI             string         `gorm:"index;size:36" json:"jti"`               // Access Token ID
	RefreshTokenJTI string         `gorm:"index;size:36" json:"refresh_token_jti"` // Refresh Token ID
	DeviceInfo      string         `gorm:"size:255" json:"device_info"`            // Parsed OS/Browser
	LoginAt         time.Time      `gorm:"index;not null" json:"login_at"`
	ExpiresAt       *time.Time     `json:"expires_at"`                             // Access Token expiry
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	// Relations
	User User `gorm:"foreignKey:UserID" json:"-"`
}

// TableName specifies the table name
func (LoginHistory) TableName() string {
	return "login_histories"
}
