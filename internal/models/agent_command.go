package models

import (
    "time"
)

// AgentCommand represents a server-issued command for an agent to execute
type AgentCommand struct {
    ID          uint       `gorm:"primaryKey" json:"id"`
    HostID      uint       `gorm:"index;not null" json:"host_id"`
    Command     string     `gorm:"size:64;not null" json:"command"`
    Processed   bool       `gorm:"default:false" json:"processed"`
    ProcessedAt *time.Time `json:"processed_at"`
    CreatedAt   time.Time  `json:"created_at"`
}

func (AgentCommand) TableName() string { return "agent_commands" }
