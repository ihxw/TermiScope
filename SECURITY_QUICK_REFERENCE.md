# 安全功能快速参考

## 1. SSH 主机密钥验证

### 使用示例

```go
import "github.com/ihxw/termiscope/internal/utils"

// 创建带验证的 SSH 配置
sshConfig, err := utils.CreateSSHConfigWithVerification(
    db,              // 数据库连接
    hostID,          // 主机 ID
    username,        // SSH 用户名
    authMethods,     // 认证方法
    fingerprint,     // 已保存的指纹（空表示首次连接）
    func(fp string) error {
        // 首次连接时的回调：保存指纹
        host.Fingerprint = fp
        return db.Save(&host).Error
    },
    10*time.Second,  // 超时时间
)

// 使用配置建立连接
client, err := ssh.Dial("tcp", addr, sshConfig)
```

### 安全事件

- **SSH_HOST_KEY_MISMATCH** (CRITICAL): 指纹不匹配，可能遭受 MITM 攻击
- **LOGIN_SUCCESS** (LOW): 首次连接并保存指纹

---

## 2. 命令注入防护

### Shell 转义

```go
import "github.com/ihxw/termiscope/internal/utils"

// 转义单个参数
safePath := utils.ShellEscape(userInput)
// "file;rm -rf /" → 'file;rm -rf /'
// "$HOME" → '$HOME'
// "it's" → 'it'\''s'

// 转义多个参数
args := utils.ShellEscapeSlice([]string{arg1, arg2, arg3})
```

### 使用示例

```go
// 不安全的方式
output, err := session.Output(fmt.Sprintf("du -sk '%s'", path))

// 安全的方式
escapedPath := utils.ShellEscape(path)
output, err := session.Output("du -sk " + escapedPath)
```

### 验证命令

```go
// 检查命令是否包含危险字符
if utils.ValidateShellCommand(cmd) {
    log.Println("⚠️ 检测到可疑命令")
}
```

---

## 3. 安全事件审计

### 记录事件

```go
import "github.com/ihxw/termiscope/internal/models"

// 记录安全事件
models.SecurityEventLog(
    db,
    models.LoginFailed,      // 事件类型
    models.SeverityMedium,   // 严重级别
    userID,                  // 用户 ID
    username,                // 用户名
    ipAddress,               // IP 地址
    userAgent,               // User-Agent
    "密码错误",              // 详情
    map[string]interface{}{  // 元数据（可选）
        "attempt": 3,
        "method": "password",
    },
)
```

### 事件类型

```go
// 认证相关
models.LoginFailed          // 登录失败
models.LoginSuccess         // 登录成功
models.Logout               // 登出
models.TokenRevoked         // Token 吊销

// 安全威胁
models.BruteForceDetected   // 暴力破解检测
models.SSHHostKeyMismatch   // SSH 密钥不匹配
models.CommandInjection     // 命令注入尝试
models.SuspiciousActivity   // 可疑活动

// 权限相关
models.PermissionDenied     // 权限拒绝

// 配置变更
models.PasswordChanged      // 密码修改
models.TwoFAEnabled         // 启用 2FA
models.TwoFADisabled        // 禁用 2FA
models.ConfigChanged        // 配置变更
models.DataExport           // 数据导出
```

### 严重级别

```go
models.SeverityLow       // 低 - 常规事件
models.SeverityMedium    // 中 - 需要注意
models.SeverityHigh      // 高 - 需要立即关注
models.SeverityCritical  // 严重 - 严重威胁
```

### 暴力破解检测

```go
// 检查 IP 是否存在暴力破解行为
if models.CheckBruteForce(db, ipAddress, 15*time.Minute, 10) {
    // 15 分钟内失败 10 次，触发告警
    models.SecurityEventLog(db, models.BruteForceDetected, models.SeverityHigh, ...)
}
```

### 查询事件

```go
// 获取用户的安全事件
events := models.GetUserSecurityEvents(db, userID, 100)

// 获取最近的高风险事件
highEvents := models.GetRecentSecurityEvents(db, "", models.SeverityHigh, 50)

// 按类型筛选
loginFails := models.GetRecentSecurityEvents(db, models.LoginFailed, "", 100)
```

---

## 4. 日志脱敏

### 自动脱敏

所有通过 `utils.LogError()` 的日志都会自动脱敏：

```go
import "github.com/ihxw/termiscope/internal/utils"

// 自动脱敏密码
utils.LogError("用户登录失败：password=%s", password)
// 输出：用户登录失败：password=***REDACTED***

// 自动脱敏 Token
utils.LogError("API 请求：Bearer %s", token)
// 输出：API 请求：Bearer ***REDACTED***

// 自动脱敏密钥
utils.LogError("配置密钥：%s", apiKey)
// 输出：配置密钥：***REDACTED***
```

### 手动脱敏

```go
// 手动脱敏消息
safeMsg := utils.SanitizeLog(sensitiveMessage)
log.Println(safeMsg)
```

### 脱敏模式

```go
// 内置脱敏模式
- password/passwd/pwd = ***REDACTED***
- token/secret/key/api_key = ***REDACTED***
- Bearer JWT Token = Bearer ***REDACTED***
- Authorization Header = Authorization: ***REDACTED***
- 32 位十六进制 = ***REDACTED_HEX***
```

---

## 最佳实践

### ✅ DO (推荐)

```go
// 1. 始终使用 Shell 转义
cmd := "ls -la " + utils.ShellEscape(userPath)

// 2. 记录所有安全事件
models.SecurityEventLog(db, eventType, severity, ...)

// 3. 使用日志脱敏
utils.LogError("敏感操作：%s", sensitiveData)

// 4. 验证 SSH 主机密钥
sshConfig, _ := utils.CreateSSHConfigWithVerification(...)
```

### ❌ DON'T (禁止)

```go
// 1. 不要直接拼接用户输入
cmd := "ls -la " + userInput  // ❌ 危险！

// 2. 不要在日志中记录明文密码
log.Printf("password=%s", password)  // ❌ 泄露！

// 3. 不要忽略 SSH 指纹验证
sshConfig.HostKeyCallback = ssh.InsecureIgnoreHostKey()  // ❌ 危险！

// 4. 不要跳过安全事件记录
// 忽略登录失败  // ❌ 无法检测攻击！
```

---

## 故障排除

### SSH 连接失败

**问题**: "host key fingerprint mismatch"

**原因**: 远程主机的密钥指纹与数据库中保存的不匹配

**解决方案**:
1. 确认是否是中间人攻击
2. 如果是合法的密钥变更，清除数据库中的旧指纹
3. 重新连接会自动保存新指纹

```sql
-- 清除特定主机的指纹
UPDATE ssh_hosts SET fingerprint = '' WHERE id = ?;
```

### 命令执行失败

**问题**: Shell 转义后命令不工作

**原因**: 某些特殊字符被过度转义

**解决方案**:
1. 检查命令是否需要 Shell 特性（管道、重定向等）
2. 如果不需要，使用 `session.Output(cmd)` 直接执行
3. 如果需要，确保正确转义每个参数

### 安全事件未记录

**问题**: 安全事件未出现在数据库

**原因**:
1. 数据库连接问题
2. 表结构未创建

**解决方案**:
```bash
# 运行数据库迁移
make migrate
# 或手动创建表
```

```sql
CREATE TABLE security_events (
    id INTEGER PRIMARY KEY,
    user_id INTEGER,
    event_type TEXT,
    severity TEXT,
    ip_address TEXT,
    details TEXT,
    created_at DATETIME
);
```

---

## 性能影响

| 功能 | 延迟增加 | 内存增加 | CPU 增加 |
|------|---------|---------|---------|
| SSH 验证 | < 1ms | < 1KB | < 0.1% |
| Shell 转义 | < 0.1ms | < 1KB | < 0.01% |
| 安全事件 | 异步 | < 10KB | < 0.1% |
| 日志脱敏 | < 0.1ms | < 1KB | < 0.01% |

**总体影响**: 可忽略不计 ✅

---

## 相关文档

- [SECURITY_AUDIT.md](./SECURITY_AUDIT.md) - 完整审计报告
- [SECURITY_FIXES_COMPLETED.md](./SECURITY_FIXES_COMPLETED.md) - 实施详情
- [SECURITY_FIXES_SUMMARY.md](./SECURITY_FIXES_SUMMARY.md) - 总结报告

---

**最后更新**: 2026-03-19  
**版本**: 1.0  
**状态**: 生产就绪
