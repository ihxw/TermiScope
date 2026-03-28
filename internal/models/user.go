package models

import (
	"crypto/md5"
	"encoding/hex"
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

// UserDTO is the safe representation of a user without sensitive fields
type UserDTO struct {
	ID               uint       `json:"id"`
	Username         string     `json:"username"`
	Email            string     `json:"email"`
	DisplayName      string     `json:"display_name"`
	Role             string     `json:"role"`
	Status           string     `json:"status"`
	TwoFactorEnabled bool       `json:"two_factor_enabled"`
	CreatedAt        time.Time  `json:"created_at"`
	UpdatedAt        time.Time  `json:"updated_at"`
	LastLoginAt      *time.Time `json:"last_login_at"`
}

// ToDTO converts a User to UserDTO
func (u *User) ToDTO() UserDTO {
	return UserDTO{
		ID:               u.ID,
		Username:         u.Username,
		Email:            u.Email,
		DisplayName:      u.DisplayName,
		Role:             u.Role,
		Status:           u.Status,
		TwoFactorEnabled: u.TwoFactorEnabled,
		CreatedAt:        u.CreatedAt,
		UpdatedAt:        u.UpdatedAt,
		LastLoginAt:      u.LastLoginAt,
	}
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
	valid, _ := u.CheckPasswordWithMigration(password)
	return valid
}

// CheckPasswordWithMigration checks if the password matches and if it requires an MD5->Bcrypt upgrade
func (u *User) CheckPasswordWithMigration(password string) (bool, bool) {
	// First check direct bcrypt
	err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password))
	if err == nil {
		return true, false // Matches, no upgrade needed
	}

	// Fallback to testing MD5 for legacy hashes
	md5Hash := md5.Sum([]byte(password))
	md5Str := hex.EncodeToString(md5Hash[:])

	err = bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(md5Str))
	if err == nil {
		return true, true // Matches, BUT requires upgrade
	}

	return false, false // Doesn't match
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
