package config

import (
	"fmt"
	"strconv"

	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

// Default settings hardcoded as requested
var defaultSettings = map[string]string{
	"ssh.timeout":                  "30s",
	"ssh.idle_timeout":             "30m",
	"ssh.max_connections_per_user": "10",
	"security.login_rate_limit":    "20",
	"security.access_expiration":   "60m",
	"security.refresh_expiration":  "168h",
}

// SyncConfigFromDB loads settings from DB into config, seeding defaults if missing
func SyncConfigFromDB(db *gorm.DB, cfg *Config) error {
	// Ensure table exists (AutoMigrate should have run, but just in case)
	if !db.Migrator().HasTable(&models.SystemConfig{}) {
		return fmt.Errorf("system_config table not found")
	}

	for key, defaultValue := range defaultSettings {
		var setting models.SystemConfig
		err := db.Where("config_key = ?", key).First(&setting).Error

		if err == gorm.ErrRecordNotFound {
			// Seed default
			setting = models.SystemConfig{
				ConfigKey:   key,
				ConfigValue: defaultValue,
				Description: fmt.Sprintf("System setting for %s", key),
			}
			if err := db.Create(&setting).Error; err != nil {
				return fmt.Errorf("failed to seed setting %s: %w", key, err)
			}
		} else if err != nil {
			return err
		}

		// Update in-memory config
		if err := updateConfigValue(cfg, key, setting.ConfigValue); err != nil {
			return fmt.Errorf("failed to load setting %s: %w", key, err)
		}
	}

	// Load allowed_origins from database
	dbOrigins, err := LoadAllowedOrigins(db)
	if err != nil {
		return fmt.Errorf("failed to load allowed_origins: %w", err)
	}

	// Merge with file-based origins (from config.yaml)
	// Create a map to deduplicate
	originMap := make(map[string]bool)

	// Add file-based origins first
	for _, origin := range cfg.Server.AllowedOrigins {
		originMap[origin] = true
	}

	// Add database origins
	for _, origin := range dbOrigins {
		originMap[origin] = true
	}

	// Convert back to slice
	mergedOrigins := make([]string, 0, len(originMap))
	for origin := range originMap {
		mergedOrigins = append(mergedOrigins, origin)
	}

	cfg.Server.AllowedOrigins = mergedOrigins

	return nil
}

// updateConfigValue parses the string value and updates the Config struct
func updateConfigValue(cfg *Config, key, value string) error {
	var err error
	switch key {
	case "ssh.timeout":
		cfg.SSH.Timeout = value
	case "ssh.idle_timeout":
		cfg.SSH.IdleTimeout = value
	case "ssh.max_connections_per_user":
		cfg.SSH.MaxConnectionsPerUser, err = strconv.Atoi(value)
	case "security.login_rate_limit":
		cfg.Security.LoginRateLimit, err = strconv.Atoi(value)
	case "security.access_expiration":
		cfg.Security.AccessExpiration = value
	case "security.refresh_expiration":
		cfg.Security.RefreshExpiration = value
	}
	return err
}

// SaveAllowedOrigins saves allowed origins to database
func SaveAllowedOrigins(db *gorm.DB, origins []string) error {
	// Convert to JSON
	var originsJSON string
	if len(origins) > 0 {
		// Simple JSON array construction
		originsJSON = "["
		for i, origin := range origins {
			if i > 0 {
				originsJSON += ","
			}
			originsJSON += fmt.Sprintf("\"%s\"", origin)
		}
		originsJSON += "]"
	} else {
		originsJSON = "[]"
	}

	var config models.SystemConfig
	result := db.Where("config_key = ?", "server.allowed_origins").First(&config)

	if result.Error == gorm.ErrRecordNotFound {
		// Create new record
		config = models.SystemConfig{
			ConfigKey:   "server.allowed_origins",
			ConfigValue: originsJSON,
			Description: "List of allowed origins for CORS and WebSocket",
		}
		return db.Create(&config).Error
	}

	// Update existing record
	return db.Model(&config).Update("config_value", originsJSON).Error
}

// LoadAllowedOrigins loads allowed origins from database
func LoadAllowedOrigins(db *gorm.DB) ([]string, error) {
	var config models.SystemConfig
	err := db.Where("config_key = ?", "server.allowed_origins").First(&config).Error

	if err == gorm.ErrRecordNotFound {
		return []string{}, nil
	}
	if err != nil {
		return nil, err
	}

	// Simple JSON parsing (assuming format: ["origin1","origin2"])
	value := config.ConfigValue
	if value == "" || value == "[]" {
		return []string{}, nil
	}

	// Remove brackets and quotes
	value = value[1 : len(value)-1] // Remove [ and ]
	if value == "" {
		return []string{}, nil
	}

	// Split by comma
	parts := make([]string, 0)
	for _, part := range splitJSON(value) {
		// Remove quotes
		origin := part[1 : len(part)-1]
		parts = append(parts, origin)
	}

	return parts, nil
}

// splitJSON splits JSON array elements (simple implementation)
func splitJSON(s string) []string {
	result := make([]string, 0)
	current := ""
	inQuote := false

	for _, char := range s {
		if char == '"' {
			inQuote = !inQuote
			current += string(char)
		} else if char == ',' && !inQuote {
			if current != "" {
				result = append(result, current)
				current = ""
			}
		} else {
			current += string(char)
		}
	}

	if current != "" {
		result = append(result, current)
	}

	return result
}
