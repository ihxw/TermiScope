package config

import (
	"fmt"
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
	SMTPTLSSkipVerify bool   `mapstructure:"smtp_tls_skip_verify"` // WARNING: should be false in production
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
	viper.SetDefault("server.allowed_origins", []string{}) // Empty = no CORS by default
	viper.SetDefault("server.max_upload_size", 10485760)   // 10MB
	viper.SetDefault("database.path", "./data/termiscope.db")
	viper.SetDefault("ssh.timeout", "30s")
	viper.SetDefault("ssh.idle_timeout", "30m")
	viper.SetDefault("ssh.max_connections_per_user", 10)
	viper.SetDefault("security.login_rate_limit", 20)
	viper.SetDefault("security.access_expiration", "60m")
	viper.SetDefault("security.refresh_expiration", "168h") // 7 days
	viper.SetDefault("security.smtp_tls_skip_verify", false)
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

	// Generate secrets if not provided
	if config.Security.JWTSecret == "" {
		config.Security.JWTSecret = os.Getenv("TERMISCOPE_JWT_SECRET")
		if config.Security.JWTSecret == "" {
			return nil, fmt.Errorf("JWT secret is required (set TERMISCOPE_JWT_SECRET environment variable)")
		}
	}

	if config.Security.EncryptionKey == "" {
		config.Security.EncryptionKey = os.Getenv("TERMISCOPE_ENCRYPTION_KEY")
		if config.Security.EncryptionKey == "" {
			return nil, fmt.Errorf("encryption key is required (set TERMISCOPE_ENCRYPTION_KEY environment variable)")
		}
	}

	// Validate encryption key length (must be 32 bytes for AES-256)
	if len(config.Security.EncryptionKey) != 32 {
		return nil, fmt.Errorf("encryption key must be exactly 32 bytes for AES-256, got %d bytes", len(config.Security.EncryptionKey))
	}

	// Validate JWT secret strength (minimum 32 bytes)
	if len(config.Security.JWTSecret) < 32 {
		return nil, fmt.Errorf("JWT secret must be at least 32 bytes for security, got %d bytes", len(config.Security.JWTSecret))
	}

	// Warn if SMTP TLS verification is disabled
	if config.Security.SMTPTLSSkipVerify {
		fmt.Println("WARNING: SMTP TLS certificate verification is disabled. This is insecure and should only be used for testing.")
	}

	return &config, nil
}

// SaveConfig writes the current configuration back to the config file
func (c *Config) SaveConfig() error {
	viper.Set("server.port", c.Server.Port)
	viper.Set("server.mode", c.Server.Mode)
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
