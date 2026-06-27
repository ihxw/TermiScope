package models

import "time"

type MonitorRecord struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	HostID    uint      `json:"host_id" gorm:"index"`
	CPU       float64   `json:"cpu"`
	MemUsed   uint64    `json:"mem_used"`
	MemTotal  uint64    `json:"mem_total"`
	DiskUsed  uint64    `json:"disk_used"`
	DiskTotal uint64    `json:"disk_total"`
	NetRx     uint64    `json:"net_rx"`
	NetTx     uint64    `json:"net_tx"`
	CreatedAt time.Time `json:"created_at" gorm:"index"`
}
