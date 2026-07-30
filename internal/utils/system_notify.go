package utils

import (
	"log"
	"strings"
	"time"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// LoadSystemConfigMap loads notification-related system_config rows.
func LoadSystemConfigMap(db *gorm.DB, encryptionKey string) map[string]string {
	var configs []models.SystemConfig
	db.Where("config_key LIKE ? OR config_key LIKE ? OR config_key = ? OR config_key = ?",
		"smtp_%", "telegram_%", "notification_template", "system_notify_channels").Find(&configs)

	configMap := make(map[string]string)
	for _, c := range configs {
		configMap[c.ConfigKey] = c.ConfigValue
	}
	for _, key := range []string{"smtp_password", "telegram_bot_token"} {
		if v, ok := configMap[key]; ok && v != "" {
			configMap[key] = DecryptSystemConfig(v, encryptionKey)
		}
	}
	return configMap
}

// SendSystemAlert sends to channels configured under System Settings (email / telegram).
func SendSystemAlert(db *gorm.DB, encryptionKey, subject, message string) {
	configMap := LoadSystemConfigMap(db, encryptionKey)
	channels := strings.ToLower(strings.TrimSpace(configMap["system_notify_channels"]))
	if channels == "" {
		channels = "email,telegram"
	}

	tmpl := configMap["notification_template"]
	if tmpl == "" {
		tmpl = DefaultNotificationTemplate
	}

	finalMsg := strings.ReplaceAll(tmpl, "{{emoji}}", "⚠️")
	finalMsg = strings.ReplaceAll(finalMsg, "{{event}}", subject)
	finalMsg = strings.ReplaceAll(finalMsg, "{{client}}", "TermiScope")
	finalMsg = strings.ReplaceAll(finalMsg, "{{message}}", message)
	finalMsg = strings.ReplaceAll(finalMsg, "{{time}}", time.Now().Format("2006-01-02 15:04:05"))

	if strings.Contains(channels, "email") {
		to := configMap["smtp_to"]
		if configMap["smtp_server"] != "" && configMap["smtp_from"] != "" && to != "" {
			go func() {
				if err := SendEmail(configMap, to, subject, finalMsg); err != nil {
					log.Printf("System alert email failed: %v", err)
				}
			}()
		} else {
			log.Printf("System alert: email channel enabled but SMTP is not fully configured")
		}
	}

	if strings.Contains(channels, "telegram") {
		if configMap["telegram_bot_token"] != "" && configMap["telegram_chat_id"] != "" {
			go func() {
				if err := SendTelegram(configMap, finalMsg); err != nil {
					log.Printf("System alert telegram failed: %v", err)
				}
			}()
		} else {
			log.Printf("System alert: telegram channel enabled but Telegram is not fully configured")
		}
	}
}
