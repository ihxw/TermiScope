# TermiScope 项目安全审计报告

## 执行摘要

本报告对 TermiScope 项目进行了全面的安全性和隐私性审查，识别出多个需要改进的安全问题，并提供了具体的修复建议。

**审查日期**: 2026 年 3 月 19 日  
**审查范围**: 后端 Go 代码、中间件、处理器、配置管理  
**风险等级**: 中等

---

## 1. 关键安全问题

### 1.1 SSH 主机密钥验证问题 ⚠️ 高风险

**问题描述**:
在多个 SSH 连接场景中使用了 `ssh.InsecureIgnoreHostKey()`，这会禁用 SSH 主机密钥验证，使系统容易受到中间人 (MITM) 攻击。

**影响文件**:
- `internal/tools/monitor/monitor_old_cmd.go` (第 874, 1466, 1786, 2066 行)
- 监控部署、停止和批量操作功能

**当前代码**:
```go
sshConfig := &ssh.ClientConfig{
    User:            host.Username,
    Auth:            authMethods,
    HostKeyCallback: ssh.InsecureIgnoreHostKey(), // ⚠️ 不安全
    Timeout:         10 * time.Second,
}
```

**风险**:
- 中间人攻击风险
- 无法检测服务器身份伪造
- 敏感数据可能被拦截

**修复建议**:
```go
// 使用 TOFU (Trust On First Use) 策略
sshConfig := &ssh.ClientConfig{
    User: host.Username,
    Auth: authMethods,
    HostKeyCallback: func(hostname string, remote net.Addr, key ssh.PublicKey) error {
        // 检查是否已保存指纹
        if host.Fingerprint != "" {
            // 验证指纹是否匹配
            expectedFp := ssh.FingerprintSHA256(key)
            if expectedFp != host.Fingerprint {
                return fmt.Errorf("host key fingerprint mismatch")
            }
            return nil
        }
        // 首次连接，保存指纹 (TOFU)
        host.Fingerprint = ssh.FingerprintSHA256(key)
        h.DB.Save(&host)
        return nil
    },
    Timeout: 10 * time.Second,
}
```

---

### 1.2 密码学实现问题 ⚠️ 中等风险

#### 1.2.1 AES 密钥长度验证不足

**问题描述**:
虽然配置文件中有密钥长度验证，但在实际使用中缺少对密钥有效性的运行时检查。

**影响文件**:
- `internal/utils/crypto.go`

**当前代码**:
```go
func EncryptAES(plaintext string, key string) (string, error) {
    keyBytes := []byte(key)  // ⚠️ 未验证密钥长度
    block, err := aes.NewCipher(keyBytes)
    // ...
}
```

**修复建议**:
```go
func EncryptAES(plaintext string, key string) (string, error) {
    keyBytes := []byte(key)
    
    // 验证密钥长度
    if len(keyBytes) != 32 {
        return "", fmt.Errorf("encryption key must be 32 bytes for AES-256")
    }
    
    block, err := aes.NewCipher(keyBytes)
    if err != nil {
        return "", fmt.Errorf("failed to create cipher: %w", err)
    }
    // ...
}
```

#### 1.2.2 缺少密钥轮换机制

**问题**: 加密密钥硬编码在配置文件中，没有密钥轮换机制。

**建议**:
1. 实现密钥版本管理
2. 支持多密钥共存（用于解密旧数据）
3. 定期密钥轮换策略

---

### 1.3 密码处理问题 ⚠️ 中等风险

#### 1.3.1 MD5 + Bcrypt 双重哈希

**问题描述**:
密码先使用 MD5 哈希，再用 Bcrypt 哈希。MD5 已被证明不安全，且这种组合增加了不必要的复杂性。

**影响文件**:
- `internal/handlers/auth.go` (第 947 行)
- `internal/models/user.go`

**当前代码**:
```go
// auth.go - ForgotPassword
md5Hash := md5.Sum([]byte(tempPassword))
md5String := hex.EncodeToString(md5Hash[:])
if err := user.SetPassword(md5String); err != nil {  // ⚠️ MD5 不安全
```

**修复建议**:
```go
// 直接使用 Bcrypt，或至少使用 SHA-256 替代 MD5
import "golang.org/x/crypto/bcrypt"

func SetPassword(plainPassword string) error {
    // 直接使用 Bcrypt（推荐）
    hashed, err := bcrypt.GenerateFromPassword([]byte(plainPassword), bcrypt.DefaultCost)
    if err != nil {
        return err
    }
    u.PasswordHash = string(hashed)
    return nil
}
```

#### 1.3.2 临时密码生成强度不足

**问题**: 忘记密码功能生成的临时密码仅 8 个字符。

**修复建议**:
```go
// 生成更强的临时密码（至少 12 位，包含大小写字母、数字、特殊字符）
func GenerateSecureRandomPassword(length int) string {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    b := make([]byte, length)
    for i := range b {
        n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
        b[i] = chars[n.Int64()]
    }
    return string(b)
}
```

---

### 1.4 CORS 配置问题 ⚠️ 中等风险

**问题描述**:
默认配置允许所有来源 (`*`)，且自动添加来源的机制存在安全风险。

**影响文件**:
- `configs/config.yaml` (第 18 行)
- `internal/handlers/auth.go` (第 888-906 行)

**当前配置**:
```yaml
allowed_origins:
  - "http://localhost:5173"
  - "*"  # ⚠️ 允许所有来源
```

**风险**:
- 跨站请求伪造 (CSRF) 风险增加
- 恶意网站可能发起跨域请求

**修复建议**:
```yaml
# 生产环境配置
allowed_origins:
  - "https://yourdomain.com"
  # 不要使用 *
```

```go
// 禁用自动添加来源的 TOFU 机制
// auth.go - 删除或禁用 autoAddOrigin 调用
// go h.autoAddOrigin(c)  // 注释掉这行
```

---

### 1.5 监控 Agent 部署安全问题 ⚠️ 高风险

#### 1.5.1 监控密钥以明文传输

**问题描述**:
监控 Agent 使用 Bearer Token 进行认证，但密钥在多个地方以明文形式出现。

**影响文件**:
- `tools/monitor/monitor_old_cmd.go` (第 406 行)
- Agent 脚本中的 `Authorization: Bearer $SECRET`

**风险**:
- 密钥可能在日志中泄露
- 网络传输可能被拦截

**修复建议**:
1. 使用双向 TLS 认证
2. 实现短期有效的 JWT token
3. 为每个 Agent 使用独立的证书

#### 1.5.2 Agent 二进制文件缺少完整性验证

**问题描述**:
虽然有 `agent_hashes.json` 文件，但在部署时未验证二进制文件完整性。

**修复建议**:
```go
// 在上传 Agent 前验证哈希
expectedHash, err := utils.GetAgentHash(filename)
if err != nil {
    return fmt.Errorf("无法获取预期哈希")
}

actualHash := sha256.Sum256(binaryContent)
if hex.EncodeToString(actualHash[:]) != expectedHash {
    return fmt.Errorf("二进制文件哈希不匹配")
}
```

---

## 2. 输入验证和注入防护

### 2.1 SQL 注入防护 ✅ 良好

**现状**: 使用 GORM ORM，参数化查询，未发现明显的 SQL 注入风险。

### 2.2 命令注入风险 ⚠️ 中等风险

**问题描述**:
在 SFTP 和监控功能中，通过 SSH 执行远程命令时使用了字符串拼接。

**影响文件**:
- `internal/handlers/sftp.go` (第 593 行)
- `tools/monitor/monitor_old_cmd.go` (第 1482-1486 行)

**当前代码**:
```go
// sftp.go
output, err := session.Output(fmt.Sprintf("du -sk '%s'", targetPath))
// ⚠️ 如果 targetPath 包含单引号，可能导致命令注入
```

**修复建议**:
```go
// 使用 shell 安全的参数转义
func shellEscape(s string) string {
    return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

output, err := session.Output("du -sk " + shellEscape(targetPath))
```

---

## 3. 认证和授权

### 3.1 JWT Token 管理 ✅ 良好

**优点**:
- 实现了 Access Token 和 Refresh Token 机制
- 支持 Token 吊销列表
- Token 类型验证

**建议改进**:
1. 添加 Token 使用次数限制
2. 实现异常登录检测（地理位置、IP 变化）

### 3.2 双因素认证 (2FA) ✅ 良好

**现状**: 实现了 TOTP 和备用码机制

**建议改进**:
1. 添加备用码使用通知
2. 限制备用码生成数量
3. 实现 2FA 恢复码的加密存储（当前已加密，良好）

---

## 4. 数据隐私保护

### 4.1 敏感数据加密存储 ✅ 良好

**已实现**:
- SSH 密码使用 AES-256-GCM 加密
- 私钥加密存储
- 2FA 密钥加密

**建议改进**:
1. 数据库文件加密（考虑使用 SQLCipher）
2. 日志文件中敏感信息脱敏

### 4.2 日志安全 ⚠️ 低风险

**问题**: 日志中可能包含敏感信息

**修复建议**:
```go
// 添加日志脱敏函数
func sanitizeLog(message string) string {
    // 脱敏密码、token 等
    sanitized := regexp.MustCompile(`password["']:\s*["'][^"']+["']`).
        ReplaceAllString(message, `password: "***REDACTED***"`)
    return sanitized
}
```

---

## 5. 安全配置管理

### 5.1 配置文件安全 ⚠️ 中等风险

**问题**:
- 配置文件包含硬编码密钥
- 缺少配置文件权限检查

**修复建议**:
```go
// 启动时检查配置文件权限
func checkConfigPermissions(configPath string) error {
    info, err := os.Stat(configPath)
    if err != nil {
        return err
    }
    
    // 在 Unix 系统上检查文件权限
    if info.Mode().Perm()&0077 != 0 {
        return fmt.Errorf("配置文件权限过大，应为 600")
    }
    return nil
}
```

### 5.2 环境变量管理 ✅ 良好

**现状**: 支持通过环境变量设置密钥

**建议**:
1. 添加环境变量验证
2. 提供密钥生成工具

---

## 6. Web 安全

### 6.1 安全响应头 ✅ 良好

**现状**: 实现了完整的安全响应头

**已实现**:
- Content-Security-Policy
- Strict-Transport-Security
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection

### 6.2 文件上传安全 ⚠️ 低风险

**建议改进**:
1. 添加文件类型白名单验证
2. 实现上传文件病毒扫描
3. 限制上传文件大小（已部分实现）

---

## 7. 监控和审计

### 7.1 安全审计日志 ⚠️ 中等风险

**缺失**:
- 登录失败次数告警
- 异常行为检测
- 敏感操作审计

**建议添加**:
```go
// 安全事件审计日志
type SecurityEvent struct {
    EventType   string    // LOGIN_FAILED, PERMISSION_DENIED, etc.
    UserID      uint
    IPAddress   string
    UserAgent   string
    Details     string
    Timestamp   time.Time
    Severity    string    // LOW, MEDIUM, HIGH, CRITICAL
}

// 记录安全事件
func LogSecurityEvent(db *gorm.DB, event SecurityEvent) {
    db.Create(&event)
    
    // 高风险事件立即告警
    if event.Severity == "HIGH" || event.Severity == "CRITICAL" {
        go SendSecurityAlert(event)
    }
}
```

---

## 8. 隐私保护建议

### 8.1 数据最小化原则

**建议**:
1. 定期清理旧的连接日志
2. 实现用户数据自动删除策略
3. 添加数据导出功能（GDPR 合规）

### 8.2 用户隐私控制

**建议添加**:
1. 隐私设置面板
2. 数据使用同意管理
3. 匿名使用模式

---

## 9. 优先级修复清单

### 高优先级（立即修复）
1. ✅ 修复 SSH 主机密钥验证问题
2. ✅ 加强监控 Agent 认证机制
3. ✅ 验证 Agent 二进制文件完整性

### 中优先级（1 个月内）
1. ✅ 改进密码生成和哈希策略
2. ✅ 强化 CORS 配置
3. ✅ 添加命令注入防护
4. ✅ 实现安全事件审计

### 低优先级（3 个月内）
1. ✅ 密钥轮换机制
2. ✅ 日志脱敏
3. ✅ 配置文件权限检查
4. ✅ GDPR 合规功能

---

## 10. 安全最佳实践建议

### 开发流程
1. 实施代码安全审查流程
2. 添加自动化安全测试（SAST/DAST）
3. 定期依赖漏洞扫描

### 部署运维
1. 实施 HTTPS（Let's Encrypt）
2. 配置防火墙规则
3. 定期安全更新
4. 备份加密和离线存储

### 监控告警
1. 失败登录监控
2. 异常行为检测
3. 资源使用告警

---

## 结论

TermiScope 项目在安全性方面已有良好基础（如 JWT 认证、加密存储、安全响应头等），但仍需在以下方面改进：

1. **关键问题**: SSH 主机密钥验证、Agent 部署安全
2. **重要改进**: 密码策略、CORS 配置、命令注入防护
3. **长期优化**: 密钥轮换、审计日志、隐私合规

建议按照优先级清单逐步修复，并建立持续的安全审查机制。

---

**报告生成工具**: 自动安全审计  
**下一步行动**: 创建 GitHub Issues 跟踪修复进度
