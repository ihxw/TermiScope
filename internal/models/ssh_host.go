package models

import (
	"time"

	"gorm.io/gorm"
)

type SSHHost struct {
	ID                  uint   `gorm:"primaryKey" json:"id"`
	UserID              uint   `gorm:"not null;index" json:"user_id"`
	Name                string `gorm:"size:100;not null" json:"name"`
	Host                string `gorm:"size:255;not null" json:"host"`
	Port                int    `gorm:"default:22" json:"port"`
	Username            string `gorm:"size:100;not null" json:"username"`
	AuthType            string `gorm:"size:20;not null" json:"auth_type"` // password or key
	Fingerprint         string `gorm:"size:255" json:"fingerprint"`       // SSH Host Key Fingerprint (TOFU)
	PasswordEncrypted   string `gorm:"type:text" json:"-"`
	PrivateKeyEncrypted string `gorm:"type:text" json:"-"`
	GroupName           string `gorm:"size:50" json:"group_name"`
	Tags                string `gorm:"size:255" json:"tags"`
	MonitorEnabled      bool   `gorm:"default:false" json:"monitor_enabled"`
	MonitorSecret       string `gorm:"size:64" json:"monitor_secret"`
	Description         string `gorm:"type:text" json:"description"`
	HostType            string `gorm:"size:20;default:'control_monitor'" json:"host_type"` // control_monitor or monitor_only
	SortOrder           int    `gorm:"default:0" json:"sort_order"`
	// Network Config
	NetInterface string `json:"net_interface" gorm:"default:'auto'"` // Selected interface
	NetResetDay  int    `json:"net_reset_day" gorm:"default:1"`      // Day of month to reset

	// Traffic Accumulators (Delta Logic)
	NetMonthlyRx       uint64 `json:"net_monthly_rx" gorm:"default:0"` // Accumulated usage this month
	NetMonthlyTx       uint64 `json:"net_monthly_tx" gorm:"default:0"`
	NetLastRawRx       uint64 `json:"net_last_raw_rx" gorm:"default:0"` // Last known raw total from agent
	NetLastRawTx       uint64 `json:"net_last_raw_tx" gorm:"default:0"`
	NetLastResetDate   string `json:"net_last_reset_date"`                   // YYYY-MM-DD
	LastAgentTimestamp int64  `json:"last_agent_timestamp" gorm:"default:0"` // Timestamp of last processed packet

	// Traffic Limit Config
	NetTrafficLimit          uint64 `json:"net_traffic_limit" gorm:"default:0"`              // Bytes, 0=unlimited
	NetTrafficUsedAdjustment uint64 `json:"net_traffic_used_adjustment" gorm:"default:0"`    // Bytes, manual correction
	NetTrafficCounterMode    string `json:"net_traffic_counter_mode" gorm:"default:'total'"` // total, rx, tx

	// Monitor Status
	AgentVersion string    `json:"agent_version" gorm:"size:20"`
	Status       string    `json:"status" gorm:"default:'offline'"` // online, offline
	LastPulse    time.Time `json:"last_pulse"`

	// Notification Config
	NotifyOfflineEnabled   bool   `json:"notify_offline_enabled" gorm:"default:true"`
	NotifyTrafficEnabled   bool   `json:"notify_traffic_enabled" gorm:"default:true"`
	NotifyOfflineThreshold int    `json:"notify_offline_threshold" gorm:"default:1"`       // Minutes
	NotifyTrafficThreshold int    `json:"notify_traffic_threshold" gorm:"default:90"`      // Percent
	NotifyChannels         string `json:"notify_channels" gorm:"default:'email,telegram'"` // comma-separated
	TrafficAlerted         bool   `json:"traffic_alerted" gorm:"default:false"`

	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	LastScanAt time.Time      `json:"last_scan_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`

	// Transient fields (not stored in database)
	Password   string `gorm:"-" json:"password,omitempty"`
	PrivateKey string `gorm:"-" json:"private_key,omitempty"`
}

// TableName specifies the table name
func (SSHHost) TableName() string {
	return "ssh_hosts"
}
