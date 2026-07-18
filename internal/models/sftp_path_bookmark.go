package models

import "time"

// SftpPathBookmark stores per-user SFTP path history and favorites on the server.
type SftpPathBookmark struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"not null;uniqueIndex:idx_sftp_path_bookmark_unique;index" json:"user_id"`
	HostID    uint      `gorm:"not null;uniqueIndex:idx_sftp_path_bookmark_unique;index" json:"host_id"`
	Type      string    `gorm:"size:20;not null;uniqueIndex:idx_sftp_path_bookmark_unique;index" json:"type"`
	Path      string    `gorm:"size:1000;not null;uniqueIndex:idx_sftp_path_bookmark_unique" json:"path"`
	Position  int       `gorm:"not null;default:0" json:"position"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (SftpPathBookmark) TableName() string {
	return "sftp_path_bookmarks"
}
