package config

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/viper"
)

// resolvedConfigPath is the absolute path to the loaded config file (if any).
var resolvedConfigPath string

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
	PublicBaseURL  string   `mapstructure:"public_base_url"`
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

// ConfigFilePath returns the absolute path of the loaded config file, if any.
func ConfigFilePath() string {
	return resolvedConfigPath
}

// findConfigFile walks up from cwd to locate configs/config.yaml (stable across go run cwd).
func findConfigFile() string {
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}
	for dir := cwd; ; dir = filepath.Dir(dir) {
		p := filepath.Join(dir, "configs", "config.yaml")
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			abs, err := filepath.Abs(p)
			if err != nil {
				return p
			}
			return abs
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
	}
	return ""
}

func envSecret(key string) (string, bool) {
	v, ok := os.LookupEnv(key)
	if !ok {
		return "", false
	}
	v = strings.TrimSpace(v)
	if v == "" {
		return "", false
	}
	return v, true
}

func resolveSecret(fileValue, envKey string) string {
	if v, ok := envSecret(envKey); ok {
		return v
	}
	if v := strings.TrimSpace(fileValue); v != "" {
		return v
	}
	return ""
}

func secretFingerprint(secret string) string {
	if len(secret) < 8 {
		return "****"
	}
	return secret[:4] + "..." + secret[len(secret)-4:]
}

// LoadConfig loads configuration from file and environment variables
func LoadConfig() (*Config, error) {
	viper.Reset()
	viper.SetConfigType("yaml")

	resolvedConfigPath = findConfigFile()
	if resolvedConfigPath != "" {
		viper.SetConfigFile(resolvedConfigPath)
	} else {
		viper.SetConfigName("config")
		viper.AddConfigPath("./configs")
		viper.AddConfigPath(".")
	}

	// Set defaults
	viper.SetDefault("server.port", 8080)
	viper.SetDefault("server.mode", "debug")
	viper.SetDefault("server.timezone", "Local")
	viper.SetDefault("server.public_base_url", "")
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

	// Environment variables override (non-secret keys only; secrets resolved explicitly below).
	viper.SetEnvPrefix("TERMISCOPE")
	viper.AutomaticEnv()
	viper.BindEnv("server.port", "TERMISCOPE_PORT")
	viper.BindEnv("server.public_base_url", "TERMISCOPE_PUBLIC_BASE_URL")
	viper.BindEnv("database.path", "TERMISCOPE_DB_PATH")

	// Read config file (optional, will use defaults if not found)
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("error reading config file: %w", err)
		}
	} else if resolvedConfigPath == "" {
		resolvedConfigPath = viper.ConfigFileUsed()
	}

	fileJWT := strings.TrimSpace(viper.GetString("security.jwt_secret"))
	fileEnc := strings.TrimSpace(viper.GetString("security.encryption_key"))

	var config Config
	if err := viper.Unmarshal(&config); err != nil {
		return nil, fmt.Errorf("error unmarshaling config: %w", err)
	}

	// Secrets: non-empty env > config file > generate once and persist.
	// Never treat empty env vars as overrides (they used to wipe file values via AutomaticEnv).
	secretsGenerated := false

	config.Security.JWTSecret = resolveSecret(
		firstNonEmpty(config.Security.JWTSecret, fileJWT),
		"TERMISCOPE_JWT_SECRET",
	)
	if config.Security.JWTSecret == "" {
		generated, err := generateRandomHex(32)
		if err != nil {
			return nil, fmt.Errorf("failed to generate JWT secret: %w", err)
		}
		config.Security.JWTSecret = generated
		secretsGenerated = true
		log.Printf("Security: Auto-generated JWT secret (first run). Set jwt_secret in %s or TERMISCOPE_JWT_SECRET.", configPathHint())
	}

	config.Security.EncryptionKey = resolveSecret(
		firstNonEmpty(config.Security.EncryptionKey, fileEnc),
		"TERMISCOPE_ENCRYPTION_KEY",
	)
	if config.Security.EncryptionKey == "" {
		generated, err := generateRandomHex(16) // 16 bytes => 32 hex chars (AES-256 key material)
		if err != nil {
			return nil, fmt.Errorf("failed to generate encryption key: %w", err)
		}
		config.Security.EncryptionKey = generated
		secretsGenerated = true
		log.Printf("Security: Auto-generated encryption key (first run). Set encryption_key in %s or TERMISCOPE_ENCRYPTION_KEY.", configPathHint())
	} else if fileEnc != "" && fileEnc != config.Security.EncryptionKey {
		log.Printf("Security: encryption_key loaded from environment (fingerprint %s); config file value ignored", secretFingerprint(config.Security.EncryptionKey))
	} else {
		log.Printf("Security: encryption_key loaded (fingerprint %s)", secretFingerprint(config.Security.EncryptionKey))
	}

	if secretsGenerated {
		if err := config.SaveConfig(); err != nil {
			log.Printf("Warning: Could not save auto-generated secrets to config file: %v", err)
			log.Printf("Warning: Host passwords and login sessions will break after each restart until jwt_secret and encryption_key are persisted in configs/config.yaml")
		} else {
			log.Printf("Security: Saved auto-generated secrets to %s", resolvedConfigPath)
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

	config.Server.PublicBaseURL = strings.TrimRight(strings.TrimSpace(config.Server.PublicBaseURL), "/")
	if config.Server.PublicBaseURL != "" {
		u, err := url.Parse(config.Server.PublicBaseURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return nil, fmt.Errorf("server.public_base_url must be an absolute http(s) URL")
		}
	}

	// Security: Reject wildcard CORS in release mode and warn on development origins.
	if config.Server.Mode == "release" {
		for _, origin := range config.Server.AllowedOrigins {
			if origin == "*" {
				return nil, fmt.Errorf("server.allowed_origins cannot contain '*' in release mode")
			}
			if isDevelopmentOrigin(origin) {
				log.Printf("WARNING: development CORS origin %q is configured in release mode", origin)
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
	viper.Set("server.public_base_url", c.Server.PublicBaseURL)
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

	target := resolvedConfigPath
	if target == "" {
		target = viper.ConfigFileUsed()
	}
	if target == "" {
		target = "./configs/config.yaml"
		abs, err := filepath.Abs(target)
		if err == nil {
			target = abs
		}
		resolvedConfigPath = target
	}

	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	viper.SetConfigFile(target)
	return viper.WriteConfig()
}

func isDevelopmentOrigin(origin string) bool {
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Hostname())
	return host == "localhost" || host == "127.0.0.1" || host == "::1" || strings.HasSuffix(host, ".localhost")
}

func configPathHint() string {
	if resolvedConfigPath != "" {
		return resolvedConfigPath
	}
	return "configs/config.yaml"
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return strings.TrimSpace(v)
		}
	}
	return ""
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
