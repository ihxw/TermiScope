package config

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"

	"github.com/spf13/viper"
)

// Version is set via ldflags during build. Default is "dev".
var Version = "dev"

type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	Database DatabaseConfig `mapstructure:"database"`
	Security SecurityConfig `mapstructure:"security"`
	SSH      SSHConfig      `mapstructure:"ssh"`
	Log      LogConfig      `mapstructure:"log"`
}

type ServerConfig struct {
	Port           int      `mapstructure:"port"`
	Mode           string   `mapstructure:"mode"` // debug or release
	AllowedOrigins []string `mapstructure:"allowed_origins"`
	MaxUploadSize  int64    `mapstructure:"max_upload_size"` // in bytes
	Timezone       string   `mapstructure:"timezone"`
}

type DatabaseConfig struct {
	Path string `mapstructure:"path"`
}

type SecurityConfig struct {
	JWTSecret         string `mapstructure:"jwt_secret"`
	EncryptionKey     string `mapstructure:"encryption_key"`
	LoginRateLimit    int    `mapstructure:"login_rate_limit"`
	AccessExpiration  string `mapstructure:"access_expiration"`
	RefreshExpiration string `mapstructure:"refresh_expiration"`
}

type SSHConfig struct {
	Timeout               string `mapstructure:"timeout"`
	IdleTimeout           string `mapstructure:"idle_timeout"`
	MaxConnectionsPerUser int    `mapstructure:"max_connections_per_user"`
}

type LogConfig struct {
	Level string `mapstructure:"level"`
	File  string `mapstructure:"file"`
}

// LoadConfig loads configuration from file and environment variables
func LoadConfig() (*Config, error) {
	viper.SetConfigName("config")
	viper.SetConfigType("yaml")
	viper.AddConfigPath("./configs")
	viper.AddConfigPath(".")

	// Set defaults
	viper.SetDefault("server.port", 8080)
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.timezone", "Local")
	viper.SetDefault("server.allowed_origins", []string{}) // Empty = same-origin only (secure default)
	viper.SetDefault("server.max_upload_size", 524288000)  // 500MB
	viper.SetDefault("database.path", "./data/termiscope.db")
	viper.SetDefault("ssh.timeout", "30s")
	viper.SetDefault("ssh.idle_timeout", "30m")
	viper.SetDefault("ssh.max_connections_per_user", 10)
	viper.SetDefault("security.login_rate_limit", 20)
	viper.SetDefault("security.access_expiration", "60m")
	viper.SetDefault("security.refresh_expiration", "168h") // 7 days
	viper.SetDefault("log.level", "info")
	viper.SetDefault("log.file", "./logs/app.log")

	// Environment variables override
	viper.SetEnvPrefix("TERMISCOPE")
	viper.AutomaticEnv()

	// Bind specific environment variables
	viper.BindEnv("server.port", "TERMISCOPE_PORT")
	viper.BindEnv("database.path", "TERMISCOPE_DB_PATH")
	viper.BindEnv("security.jwt_secret", "TERMISCOPE_JWT_SECRET")
	viper.BindEnv("security.encryption_key", "TERMISCOPE_ENCRYPTION_KEY")

	// Read config file (optional, will use defaults if not found)
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("error reading config file: %w", err)
		}
		// Config file not found, use defaults and env vars
	}

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("error unmarshaling config: %w", err)
	}

	// Auto-generate secrets if not provided (first-run experience)
	if config.Security.JWTSecret == "" {
		config.Security.JWTSecret = os.Getenv("TERMISCOPE_JWT_SECRET")
	}
	if config.Security.JWTSecret == "" {
		generated, err := generateRandomHex(32)
		if err != nil {
			return nil, fmt.Errorf("failed to generate JWT secret: %w", err)
		}
		config.Security.JWTSecret = generated
		log.Printf("Security: Auto-generated JWT secret (first run). Set TERMISCOPE_JWT_SECRET env var for production.")
	}

	if config.Security.EncryptionKey == "" {
		config.Security.EncryptionKey = os.Getenv("TERMISCOPE_ENCRYPTION_KEY")
	}
	if config.Security.EncryptionKey == "" {
		generated, err := generateRandomHex(16) // 16 bytes = 32 hex chars = 32 byte string for AES-256
		if err != nil {
			return nil, fmt.Errorf("failed to generate encryption key: %w", err)
		}
		config.Security.EncryptionKey = generated
		log.Printf("Security: Auto-generated encryption key (first run). Set TERMISCOPE_ENCRYPTION_KEY env var for production.")
	}

	// Validate encryption key length (must be 32 bytes for AES-256)
	if len(config.Security.EncryptionKey) != 32 {
		return nil, fmt.Errorf("encryption key must be exactly 32 bytes for AES-256, got %d bytes", len(config.Security.EncryptionKey))
	}

	// Validate JWT secret strength (minimum 32 bytes)
	if len(config.Security.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT secret must be at least 32 bytes for security, got %d bytes", len(config.Security.JWTSecret))
	}

	// Security: Warn about wildcard CORS in release mode
	if config.Server.Mode == "release" {
		for _, origin := range config.Server.AllowedOrigins {
			if origin == "*" {
				log.Printf("WARNING: CORS wildcard '*' is configured in release mode. This is a security risk!")
				break
			}
		}
	}

	return &config, nil
}

// SaveConfig writes the current configuration back to the config file
func (c *Config) SaveConfig() error {
	viper.Set("server.port", c.Server.Port)
	viper.Set("server.mode", c.Server.Mode)
	viper.Set("server.timezone", c.Server.Timezone)
	viper.Set("database.path", c.Database.Path)
	viper.Set("security.jwt_secret", c.Security.JWTSecret)
	viper.Set("security.encryption_key", c.Security.EncryptionKey)
	viper.Set("security.login_rate_limit", c.Security.LoginRateLimit)
	viper.Set("security.access_expiration", c.Security.AccessExpiration)
	viper.Set("security.refresh_expiration", c.Security.RefreshExpiration)
	viper.Set("ssh.timeout", c.SSH.Timeout)
	viper.Set("ssh.idle_timeout", c.SSH.IdleTimeout)
	viper.Set("ssh.max_connections_per_user", c.SSH.MaxConnectionsPerUser)
	viper.Set("log.level", c.Log.Level)
	viper.Set("log.file", c.Log.File)

	// Ensure we have a config file path set
	if viper.ConfigFileUsed() == "" {
		viper.SetConfigFile("./configs/config.yaml")
	}

	return viper.WriteConfig()
}

// AddAllowedOrigin dynamically adds an allowed origin to the configuration
func (c *Config) AddAllowedOrigin(origin string) bool {
	// Validate origin format
	if !IsValidOrigin(origin) {
		return false
	}

	// Check if already exists
	for _, existing := range c.Server.AllowedOrigins {
		if existing == origin {
			return false // Already exists
		}
	}

	// Add to in-memory configuration
	c.Server.AllowedOrigins = append(c.Server.AllowedOrigins, origin)
	return true
}

// IsValidOrigin validates if an origin should be auto-added
func IsValidOrigin(origin string) bool {
	if origin == "" {
		return false
	}

	// Parse URL
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}

	// Must be http or https
	if u.Scheme != "http" && u.Scheme != "https" {
		return false
	}

	// Exclude localhost and 127.0.0.1 (development environments should be manually configured)
	host := u.Hostname()
	if host == "localhost" || host == "127.0.0.1" || strings.HasPrefix(host, "192.168.") || strings.HasPrefix(host, "10.") {
		return false
	}

	return true
}

// ParseURL is a helper to parse URLs
func (c *Config) ParseURL(rawURL string) (*url.URL, error) {
	return url.Parse(rawURL)
}

// generateRandomHex generates a cryptographically secure random hex string
func generateRandomHex(numBytes int) (string, error) {
	b := make([]byte, numBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
