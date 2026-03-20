# TermiScope 安全修复实现指南

本文档提供了 SECURITY_AUDIT.md 中识别的安全问题的具体代码实现方案。

---

## 修复 1: SSH 主机密钥验证（TOFU 改进）

### 文件：`internal/handlers/ssh.go` (新建)

```go
package handlers

import (
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net"

	"golang.org/x/crypto/ssh"
)

// SSHKeyVerifier handles SSH host key verification with TOFU strategy
type SSHKeyVerifier struct {
	savedFingerprint string
	onNewFingerprint func(fingerprint string) error
}

// NewSSHKeyVerifier creates a new verifier
func NewSSHKeyVerifier(savedFingerprint string, onNewFingerprint func(string) error) *SSHKeyVerifier {
	return &SSHKeyVerifier{
		savedFingerprint: savedFingerprint,
		onNewFingerprint: onNewFingerprint,
	}
}

// HostKeyCallback returns an ssh.HostKeyCallback for TOFU verification
func (v *SSHKeyVerifier) HostKeyCallback() ssh.HostKeyCallback {
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		// Calculate fingerprint
		fingerprint := ssh.FingerprintSHA256(key)
		
		// If we have a saved fingerprint, verify it matches
		if v.savedFingerprint != "" {
			if fingerprint != v.savedFingerprint {
				return fmt.Errorf("⚠️ 主机密钥指纹不匹配！可能的中间人攻击。\n期望的指纹：%s\n实际的指纹：%s", 
					v.savedFingerprint, fingerprint)
			}
			return nil
		}
		
		// First time connection - save fingerprint (TOFU)
		if v.onNewFingerprint != nil {
			if err := v.onNewFingerprint(fingerprint); err != nil {
				return fmt.Errorf("保存主机密钥指纹失败：%w", err)
			}
		}
		
		return nil
	}
}

// GetFingerprintFromKey extracts fingerprint from a public key
func GetFingerprintFromKey(key ssh.PublicKey) string {
	hash := sha256.Sum256(key.Marshal())
	return "SHA256:" + base64.StdEncoding.EncodeToString(hash[:])
}
```

### 使用示例：

```go
// 在创建 SSH 客户端时使用
verifier := NewSSHKeyVerifier(host.Fingerprint, func(fp string) error {
	// 保存新指纹到数据库
	host.Fingerprint = fp
	return h.DB.Save(&host).Error
})

sshConfig := &ssh.ClientConfig{
	User: host.Username,
	Auth: authMethods,
	HostKeyCallback: verifier.HostKeyCallback(),
	Timeout: 10 * time.Second,
}
```

---

## 修复 2: 增强的密码哈希策略

### 文件：`internal/models/user.go` (修改)

```go
package models

import (
	"golang.org/x/crypto/bcrypt"
)

// SetPassword hashes and sets the user's password
func (u *User) SetPassword(plainPassword string) error {
	// 直接使用 Bcrypt，不再使用 MD5 预哈希
	// 增加 cost 因子以提高安全性（默认 10，推荐 12）
	hashed, err := bcrypt.GenerateFromPassword([]byte(plainPassword), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	u.PasswordHash = string(hashed)
	return nil
}

// CheckPassword compares plain password with hashed password
func (u *User) CheckPassword(plainPassword string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(plainPassword))
	return err == nil
}

// PasswordPolicy defines password requirements
type PasswordPolicy struct {
	MinLength     int  `json:"min_length"`
	RequireUpper  bool `json:"require_upper"`
	RequireLower  bool `json:"require_lower"`
	RequireNumber bool `json:"require_number"`
	RequireSymbol bool `json:"require_symbol"`
}

// ValidatePassword checks if password meets policy requirements
func ValidatePassword(password string, policy PasswordPolicy) error {
	if len(password) < policy.MinLength {
		return fmt.Errorf("密码长度至少为 %d 个字符", policy.MinLength)
	}
	
	hasUpper := false
	hasLower := false
	hasNumber := false
	hasSymbol := false
	
	for _, r := range password {
		switch {
		case r >= 'A' && r <= 'Z':
			hasUpper = true
		case r >= 'a' && r <= 'z':
			hasLower = true
		case r >= '0' && r <= '9':
			hasNumber = true
		default:
			hasSymbol = true
		}
	}
	
	if policy.RequireUpper && !hasUpper {
		return fmt.Errorf("密码必须包含大写字母")
	}
	if policy.RequireLower && !hasLower {
		return fmt.Errorf("密码必须包含小写字母")
	}
	if policy.RequireNumber && !hasNumber {
		return fmt.Errorf("密码必须包含数字")
	}
	if policy.RequireSymbol && !hasSymbol {
		return fmt.Errorf("密码必须包含特殊字符")
	}
	
	return nil
}
```

---

## 修复 3: 安全的随机密码生成

### 文件：`internal/utils/random.go` (修改)

```go
package utils

import (
	"crypto/rand"
	"fmt"
	"math/big"
)

// GenerateSecurePassword generates a cryptographically secure random password
func GenerateSecurePassword(length int) (string, error) {
	if length < 12 {
		length = 12 // 最小长度 12
	}
	
	// 包含大小写字母、数字和特殊字符
	const (
		lowercase = "abcdefghijklmnopqrstuvwxyz"
		uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		numbers   = "0123456789"
		symbols   = "!@#$%^&*()_+-=[]{}|;:,.<>?"
		allChars  = lowercase + uppercase + numbers + symbols
	)
	
	password := make([]byte, length)
	
	// 确保至少包含每种类型的字符
	password[0] = lowercase[randomInt(len(lowercase))]
	password[1] = uppercase[randomInt(len(uppercase))]
	password[2] = numbers[randomInt(len(numbers))]
	password[3] = symbols[randomInt(len(symbols))]
	
	// 随机填充剩余字符
	for i := 4; i < length; i++ {
		password[i] = allChars[randomInt(len(allChars))]
	}
	
	// 打乱密码
	shufflePassword(password)
	
	return string(password), nil
}

func randomInt(max int) int {
	n, err := rand.Int(rand.Reader, big.NewInt(int64(max)))
	if err != nil {
		panic(err)
	}
	return int(n.Int64())
}

func shufflePassword(password []byte) {
	for i := len(password) - 1; i > 0; i-- {
		j := randomInt(i + 1)
		password[i], password[j] = password[j], password[i]
	}
}
```

---

## 修复 4: 命令注入防护

### 文件：`internal/utils/shell.go` (新建)

```go
package utils

import (
	"strings"
)

// ShellEscape safely escapes shell arguments to prevent command injection
func ShellEscape(arg string) string {
	// 如果参数为空，返回空字符串
	if arg == "" {
		return "''"
	}
	
	// 检查是否包含需要转义的字符
	needsQuoting := false
	for _, r := range arg {
		if r == ' ' || r == '\t' || r == '\n' ||
		   r == '\'' || r == '"' || r == '\\' ||
		   r == '$' || r == '`' || r == '|' ||
		   r == '&' || r == ';' || r == '<' ||
		   r == '>' || r == '(' || r == ')' ||
		   r == '{' || r == '}' || r == '[' ||
		   r == ']' || r == '*' || r == '?' ||
		   r == '#' || r == '~' || r == '=' {
			needsQuoting = true
			break
		}
	}
	
	if !needsQuoting {
		return arg
	}
	
	// 使用单引号包裹，并转义内部的单引号
	// ' becomes '\''
	escaped := strings.ReplaceAll(arg, "'", "'\\''")
	return "'" + escaped + "'"
}

// ShellEscapeSlice escapes multiple arguments
func ShellEscapeSlice(args []string) []string {
	escaped := make([]string, len(args))
	for i, arg := range args {
		escaped[i] = ShellEscape(arg)
	}
	return escaped
}
```

### 使用示例：

```go
// 在 sftp.go 中
import "github.com/ihxw/termiscope/internal/utils"

// 原来的代码
output, err := session.Output(fmt.Sprintf("du -sk '%s'", targetPath))

// 修改为
escapedPath := utils.ShellEscape(targetPath)
output, err := session.Output("du -sk " + escapedPath)

// 或者使用多个参数
cmd := fmt.Sprintf("du -sk %s", utils.ShellEscape(targetPath))
output, err := session.Output(cmd)
```

---

## 修复 5: 增强的加密密钥管理

### 文件：`internal/utils/crypto.go` (修改)

```go
package utils

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"sync"
	"time"
)

// KeyVersion represents a versioned encryption key
type KeyVersion struct {
	Version   int
	Key       string
	CreatedAt time.Time
	Active    bool
}

// KeyManager manages multiple encryption keys for rotation
type KeyManager struct {
	keys      map[int]*KeyVersion
	currentID int
	mu        sync.RWMutex
}

// NewKeyManager creates a new key manager
func NewKeyManager() *KeyManager {
	return &KeyManager{
		keys:      make(map[int]*KeyVersion),
		currentID: 0,
	}
}

// AddKey adds a new encryption key
func (km *KeyManager) AddKey(version int, key string) error {
	km.mu.Lock()
	defer km.mu.Unlock()
	
	// 验证密钥长度
	if len(key) != 32 {
		return fmt.Errorf("密钥必须为 32 字节 (AES-256)，当前长度：%d", len(key))
	}
	
	km.keys[version] = &KeyVersion{
		Version:   version,
		Key:       key,
		CreatedAt: time.Now(),
		Active:    version == km.currentID,
	}
	
	return nil
}

// SetCurrentKey sets the current active key version
func (km *KeyManager) SetCurrentKey(version int) error {
	km.mu.Lock()
	defer km.mu.Unlock()
	
	if _, exists := km.keys[version]; !exists {
		return fmt.Errorf("密钥版本 %d 不存在", version)
	}
	
	// 更新所有密钥的活跃状态
	for v := range km.keys {
		km.keys[v].Active = (v == version)
	}
	
	km.currentID = version
	return nil
}

// EncryptAES encrypts using the current active key
func (km *KeyManager) EncryptAES(plaintext string) (string, error) {
	km.mu.RLock()
	currentKey := km.keys[km.currentID].Key
	keyVersion := km.currentID
	km.mu.RUnlock()
	
	ciphertext, err := EncryptAES(plaintext, currentKey)
	if err != nil {
		return "", err
	}
	
	// 在密文前添加密钥版本信息
	versionPrefix := fmt.Sprintf("v%d:", keyVersion)
	return versionPrefix + ciphertext, nil
}

// DecryptAES decrypts using the appropriate key version
func (km *KeyManager) DecryptAES(ciphertext string) (string, error) {
	km.mu.RLock()
	defer km.mu.RUnlock()
	
	// 解析密钥版本
	var version int
	var actualCiphertext string
	
	if len(ciphertext) > 3 && ciphertext[0] == 'v' {
		// 提取版本号
		for i := 1; i < len(ciphertext); i++ {
			if ciphertext[i] == ':' {
				fmt.Sscanf(ciphertext[1:i], "%d", &version)
				actualCiphertext = ciphertext[i+1:]
				break
			}
		}
	}
	
	// 如果没有版本信息，使用当前密钥
	if version == 0 {
		version = km.currentID
		actualCiphertext = ciphertext
	}
	
	// 查找对应的密钥
	keyVersion, exists := km.keys[version]
	if !exists {
		return "", fmt.Errorf("未知的密钥版本：%d", version)
	}
	
	return DecryptAES(actualCiphertext, keyVersion.Key)
}

// GetActiveKeyVersion returns the current active key version
func (km *KeyManager) GetActiveKeyVersion() int {
	km.mu.RLock()
	defer km.mu.RUnlock()
	return km.currentID
}

// RotateKey generates a new key and sets it as active
func (km *KeyManager) RotateKey() (int, error) {
	km.mu.Lock()
	defer km.mu.Unlock()
	
	// 生成新密钥
	keyBytes := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, keyBytes); err != nil {
		return 0, fmt.Errorf("生成密钥失败：%w", err)
	}
	newKey := base64.StdEncoding.EncodeToString(keyBytes)
	
	// 新密钥版本号
	newVersion := km.currentID + 1
	
	km.keys[newVersion] = &KeyVersion{
		Version:   newVersion,
		Key:       newKey,
		CreatedAt: time.Now(),
		Active:    true,
	}
	
	// 更新当前密钥
	km.currentID = newVersion
	
	return newVersion, nil
}

// EncryptAES encrypts plaintext using AES-256-GCM (保持向后兼容)
func EncryptAES(plaintext string, key string) (string, error) {
	if plaintext == "" {
		return "", nil
	}
	
	keyBytes := []byte(key)
	
	// 验证密钥长度
	if len(keyBytes) != 32 {
		return "", fmt.Errorf("加密密钥必须为 32 字节 (AES-256)，当前长度：%d", len(keyBytes))
	}
	
	plaintextBytes := []byte(plaintext)
	
	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", fmt.Errorf("创建密码失败：%w", err)
	}
	
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建 GCM 失败：%w", err)
	}
	
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("生成 nonce 失败：%w", err)
	}
	
	ciphertext := gcm.Seal(nonce, nonce, plaintextBytes, nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// DecryptAES decrypts ciphertext using AES-256-GCM (保持向后兼容)
func DecryptAES(ciphertext string, key string) (string, error) {
	if ciphertext == "" {
		return "", nil
	}
	
	keyBytes := []byte(key)
	
	// 验证密钥长度
	if len(keyBytes) != 32 {
		return "", fmt.Errorf("解密密钥必须为 32 字节 (AES-256)，当前长度：%d", len(keyBytes))
	}
	
	ciphertextBytes, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", fmt.Errorf("解码密文失败：%w", err)
	}
	
	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", fmt.Errorf("创建密码失败：%w", err)
	}
	
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("创建 GCM 失败：%w", err)
	}
	
	nonceSize := gcm.NonceSize()
	if len(ciphertextBytes) < nonceSize {
		return "", "密文过短"
	}
	
	nonce, ciphertextBytes := ciphertextBytes[:nonceSize], ciphertextBytes[nonceSize:]
	plaintext, err := gcm.Open(nil, nonce, ciphertextBytes, nil)
	if err != nil {
		return "", fmt.Errorf("解密失败：%w", err)
	}
	
	return string(plaintext), nil
}
```

---

## 修复 6: 安全事件审计

### 文件：`internal/models/security_event.go` (新建)

```go
package models

import (
	"time"
)

// SecurityEventType defines types of security events
type SecurityEventType string

const (
	LoginFailed          SecurityEventType = "LOGIN_FAILED"
	LoginSuccess         SecurityEventType = "LOGIN_SUCCESS"
	Logout               SecurityEventType = "LOGOUT"
	TokenRevoked         SecurityEventType = "TOKEN_REVOKED"
	PermissionDenied     SecurityEventType = "PERMISSION_DENIED"
	PasswordChanged      SecurityEventType = "PASSWORD_CHANGED"
	TwoFAEnabled          SecurityEventType = "2FA_ENABLED"
	TwoFADisabled         SecurityEventType = "2FA_DISABLED"
	SSHHostKeyMismatch   SecurityEventType = "SSH_HOST_KEY_MISMATCH"
	BruteForceDetected   SecurityEventType = "BRUTE_FORCE_DETECTED"
	SuspiciousActivity   SecurityEventType = "SUSPICIOUS_ACTIVITY"
	DataExport           SecurityEventType = "DATA_EXPORT"
	ConfigChanged        SecurityEventType = "CONFIG_CHANGED"
)

// SecurityEventSeverity defines severity levels
type SecurityEventSeverity string

const (
	SeverityLow      SecurityEventSeverity = "LOW"
	SeverityMedium   SecurityEventSeverity = "MEDIUM"
	SeverityHigh     SecurityEventSeverity = "HIGH"
	SeverityCritical SecurityEventSeverity = "CRITICAL"
)

// SecurityEvent represents a security-related event
type SecurityEvent struct {
	ID          uint                  `gorm:"primaryKey" json:"id"`
	UserID      uint                  `gorm:"index" json:"user_id"`
	Username    string                `gorm:"size:100" json:"username"`
	EventType   SecurityEventType     `gorm:"size:50;not null;index" json:"event_type"`
	Severity    SecurityEventSeverity `gorm:"size:20;not null" json:"severity"`
	IPAddress   string                `gorm:"size:45" json:"ip_address"` // IPv6
	UserAgent   string                `gorm:"type:text" json:"user_agent"`
	Details     string                `gorm:"type:text" json:"details"`
	Metadata    string                `gorm:"type:text" json:"metadata"` // JSON
	CreatedAt   time.Time             `gorm:"index" json:"created_at"`
}

// SecurityEventLog records a security event
func SecurityEventLog(db *gorm.DB, eventType SecurityEventType, severity SecurityEventSeverity,
	userID uint, username, ipAddress, userAgent, details string, metadata map[string]interface{}) {
	
	// 序列化元数据
	var metadataJSON string
	if metadata != nil {
		data, _ := json.Marshal(metadata)
		metadataJSON = string(data)
	}
	
	event := SecurityEvent{
		UserID:    userID,
		Username:  username,
		EventType: eventType,
		Severity:  severity,
		IPAddress: ipAddress,
		UserAgent: userAgent,
		Details:   details,
		Metadata:  metadataJSON,
		CreatedAt: time.Now(),
	}
	
	db.Create(&event)
	
	// 高风险事件触发告警
	if severity == SeverityHigh || severity == SeverityCritical {
		go SendSecurityAlert(event)
	}
}

// SendSecurityAlert sends alerts for high-severity events
func SendSecurityAlert(event SecurityEvent) {
	// 实现告警逻辑（邮件、Telegram、Webhook 等）
	// 这里可以根据系统配置发送不同类型的告警
	log.Printf("🚨 安全告警 [%s]: %s - 用户：%s, IP: %s",
		event.Severity, event.EventType, event.Username, event.IPAddress)
}

// CheckBruteForce checks for brute force attempts
func CheckBruteForce(db *gorm.DB, ipAddress string, window time.Duration, threshold int) bool {
	var count int64
	since := time.Now().Add(-window)
	
	db.Model(&SecurityEvent{}).
		Where("ip_address = ? AND event_type = ? AND created_at >= ?",
			ipAddress, LoginFailed, since).
		Count(&count)
	
	return count >= int64(threshold)
}

// GetUserSecurityEvents retrieves security events for a user
func GetUserSecurityEvents(db *gorm.DB, userID uint, limit int) []SecurityEvent {
	var events []SecurityEvent
	db.Where("user_id = ?", userID).
		Order("created_at DESC").
		Limit(limit).
		Find(&events)
	return events
}
```

### 使用示例：

```go
// 在 auth.go 的 Login 函数中
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// 记录无效请求
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityLow,
			0, "", c.ClientIP(), c.Request.UserAgent(), "无效请求", nil)
		utils.ErrorResponse(c, http.StatusBadRequest, "invalid request")
		return
	}
	
	// 查找用户
	var user models.User
	result := h.db.Where("username = ? OR email = ?", req.Username, req.Username).First(&user)
	if result.Error != nil {
		// 记录登录失败（未知用户）
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityLow,
			0, req.Username, c.ClientIP(), c.Request.UserAgent(), "未知用户", nil)
		
		// 检查暴力破解
		if models.CheckBruteForce(h.db, c.ClientIP(), 15*time.Minute, 10) {
			models.SecurityEventLog(h.db, models.BruteForceDetected, models.SeverityHigh,
				0, "", c.ClientIP(), c.Request.UserAgent(), "检测到暴力破解", nil)
		}
		
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}
	
	// 密码错误
	if !user.CheckPassword(req.Password) {
		models.SecurityEventLog(h.db, models.LoginFailed, models.SeverityMedium,
			user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "密码错误", nil)
		utils.ErrorResponse(c, http.StatusUnauthorized, "invalid credentials")
		return
	}
	
	// 登录成功
	models.SecurityEventLog(h.db, models.LoginSuccess, models.SeverityLow,
		user.ID, user.Username, c.ClientIP(), c.Request.UserAgent(), "登录成功", nil)
	
	// ... 其余登录逻辑
}
```

---

## 修复 7: 配置文件权限检查

### 文件：`internal/config/config.go` (修改)

```go
package config

import (
	"fmt"
	"os"
	"runtime"
)

// CheckConfigPermissions verifies config file has secure permissions
func CheckConfigPermissions(configPath string) error {
	info, err := os.Stat(configPath)
	if err != nil {
		return err
	}
	
	// 在 Unix 系统上检查权限
	if runtime.GOOS != "windows" {
		mode := info.Mode()
		// 检查其他用户是否有读/写权限（应为 600 或 640）
		if mode.Perm()&0077 != 0 {
			return fmt.Errorf("配置文件权限不安全：当前权限 %o，建议 600 或 640", mode.Perm())
		}
	}
	
	return nil
}

// SecureConfigFile creates a config file with secure permissions
func SecureConfigFile(filename string) (*os.File, error) {
	// 在 Unix 系统上创建时设置权限为 600
	if runtime.GOOS != "windows" {
		return os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	}
	// Windows 不使用 Unix 权限
	return os.OpenFile(filename, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
}
```

---

## 修复 8: 日志脱敏

### 文件：`internal/utils/logger.go` (修改)

```go
package utils

import (
	"regexp"
	"strings"
)

// SensitivePatterns defines regex patterns for sensitive data
var SensitivePatterns = []struct {
	Pattern     *regexp.Regexp
	Replacement string
}{
	{regexp.MustCompile(`(?i)(password|passwd|pwd)["']?\s*[:=]\s*["']?[^"'\s,}]+`), "$1=***REDACTED***"},
	{regexp.MustCompile(`(?i)(token|secret|key|api_key)["']?\s*[:=]\s*["']?[^"'\s,}]+`), "$1=***REDACTED***"},
	{regexp.MustCompile(`Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+`), "Bearer ***REDACTED***"},
	{regexp.MustCompile(`(?i)(authorization)\s*:\s*[A-Za-z0-9\-_]+`), "$1: ***REDACTED***"},
}

// SanitizeLog removes or masks sensitive information from log messages
func SanitizeLog(message string) string {
	sanitized := message
	
	for _, pattern := range SensitivePatterns {
		sanitized = pattern.Pattern.ReplaceAllString(sanitized, pattern.Replacement)
	}
	
	return sanitized
}

// LogError logs an error message with sanitization
func LogError(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	sanitizedMsg := SanitizeLog(msg)
	// 使用标准日志或自定义日志库
	log.Printf("ERROR: %s", sanitizedMsg)
}

// LogInfo logs an info message with sanitization
func LogInfo(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	sanitizedMsg := SanitizeLog(msg)
	log.Printf("INFO: %s", sanitizedMsg)
}

// LogDebug logs a debug message with sanitization
func LogDebug(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	sanitizedMsg := SanitizeLog(msg)
	log.Printf("DEBUG: %s", sanitizedMsg)
}
```

---

## 实施步骤

### 第一阶段（立即实施 - 1 周）
1. ✅ 实施 SSH 主机密钥验证（修复 1）
2. ✅ 添加命令注入防护（修复 4）
3. ✅ 实施安全事件审计（修复 6）

### 第二阶段（2 周内）
1. ✅ 更新密码策略（修复 2）
2. ✅ 实现安全随机密码生成（修复 3）
3. ✅ 添加日志脱敏（修复 8）

### 第三阶段（1 个月内）
1. ✅ 实施密钥管理系统（修复 5）
2. ✅ 添加配置文件权限检查（修复 7）
3. ✅ 全面测试和代码审查

---

## 测试验证

对每个修复进行单元测试和集成测试：

```bash
# 运行测试
go test ./internal/utils -v
go test ./internal/models -v
go test ./internal/handlers -v

# 安全检查
go vet ./...
gosec ./...
```

---

## 注意事项

1. **向后兼容性**: 修改密码哈希策略时，需要支持旧密码的迁移
2. **密钥轮换**: 实施密钥管理后，需要重新加密所有现有敏感数据
3. **监控**: 部署后密切监控安全事件和错误日志
4. **文档更新**: 更新用户文档和 API 文档

---

**最后更新**: 2026-03-19  
**维护者**: 安全团队
