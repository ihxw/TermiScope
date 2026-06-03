package models

import (
	"time"

	"gorm.io/gorm"
)

type CommandTemplate struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	UserID      uint           `gorm:"index;not null" json:"user_id"`
	Name        string         `gorm:"size:100;not null" json:"name"`
	Command     string         `gorm:"type:text;not null" json:"command"`
	Description string         `gorm:"type:text" json:"description"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

func (CommandTemplate) TableName() string {
	return "command_templates"
}
