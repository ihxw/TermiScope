package models

import (
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type User struct {
	ID               uint           `gorm:"primaryKey" json:"id"`
	Username         string         `gorm:"uniqueIndex;size:50;not null" json:"username"`
	PasswordHash     string         `gorm:"size:255;not null" json:"-"`
	Email            string         `gorm:"uniqueIndex;size:100;not null" json:"email"`
	DisplayName      string         `gorm:"size:100" json:"display_name"`
	Role             string         `gorm:"size:20;default:user" json:"role"`     // admin or user
	Status           string         `gorm:"size:20;default:active" json:"status"` // active or disabled
	TwoFactorEnabled bool           `gorm:"default:false" json:"two_factor_enabled"`
	TwoFactorSecret  string         `gorm:"size:255" json:"-"`  // Encrypted TOTP secret
	BackupCodes      string         `gorm:"type:text" json:"-"` // Encrypted backup codes (JSON array)
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	LastLoginAt      *time.Time     `json:"last_login_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

// SetPassword hashes and sets the user password
func (u *User) SetPassword(password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.PasswordHash = string(hash)
	return nil
}

// CheckPassword verifies the password against the hash
func (u *User) CheckPassword(password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password))
	return err == nil
}

// IsAdmin checks if the user is an admin
func (u *User) IsAdmin() bool {
	return u.Role == "admin"
}

// IsActive checks if the user is active
func (u *User) IsActive() bool {
	return u.Status == "active"
}

// TableName specifies the table name
func (User) TableName() string {
	return "users"
}
