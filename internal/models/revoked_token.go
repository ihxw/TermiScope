package models

import (
	"time"

	"gorm.io/gorm"
)

// RevokedToken stores tokens that have been logged out before expiration
type RevokedToken struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	JTI       string         `gorm:"uniqueIndex;size:36;not null" json:"jti"` // UUID
	UserID    uint           `gorm:"index" json:"user_id"`
	ExpiresAt time.Time      `gorm:"index" json:"expires_at"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName specifies the table name
func (RevokedToken) TableName() string {
	return "revoked_tokens"
}
