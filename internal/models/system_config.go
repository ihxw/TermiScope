package models

import (
	"time"

	"gorm.io/gorm"
)

type SystemConfig struct {
	ID          uint           `gorm:"primaryKey" json:"id"`
	ConfigKey   string         `gorm:"uniqueIndex;size:100;not null" json:"config_key"`
	ConfigValue string         `gorm:"type:text" json:"config_value"`
	Description string         `gorm:"type:text" json:"description"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
}

// TableName specifies the table name
func (SystemConfig) TableName() string {
	return "system_config"
}
