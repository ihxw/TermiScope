# SSH 主机密钥指纹重置指南

## 问题场景

当 VPS 重装系统后，SSH 服务会生成新的主机密钥，导致指纹与数据库中保存的不匹配，从而无法连接。

**错误信息**:
```
⚠️ 主机密钥指纹不匹配！可能的中间人攻击。
期望的指纹：SHA256:abc123...
实际的指纹：SHA256:xyz789...
```

---

## 解决方案

### 方案 1: 通过数据库重置指纹（推荐）

直接清除数据库中保存的旧指纹，让系统自动重新学习新指纹。

#### SQL 方式

```sql
-- 重置单个主机的指纹
UPDATE ssh_hosts 
SET fingerprint = '' 
WHERE id = ?;  -- 替换为主机 ID

-- 重置所有主机的指纹（批量操作）
UPDATE ssh_hosts 
SET fingerprint = '';
```

#### 使用代码

```go
// 重置特定主机的指纹
func ResetHostFingerprint(db *gorm.DB, hostID uint) error {
    return db.Model(&models.SSHHost{}).
        Where("id = ?", hostID).
        Update("fingerprint", "").Error
}

// 使用示例
err := ResetHostFingerprint(db, hostID)
if err != nil {
    log.Printf("重置指纹失败：%v", err)
    return
}
log.Println("指纹已重置，下次连接将自动保存新指纹")
```

---

### 方案 2: Web 界面重置（用户体验最佳）

在 Web 界面添加"重置指纹"按钮，用户点击后自动清除。

#### API 实现

```go
// internal/handlers/ssh_host.go

// ResetFingerprint resets the SSH host key fingerprint for a host
func (h *SSHHostHandler) ResetFingerprint(c *gin.Context) {
    userID := middleware.GetUserID(c)
    hostID := c.Param("id")
    
    var host models.SSHHost
    if err := h.db.Where("id = ? AND user_id = ?", hostID, userID).First(&host).Error; err != nil {
        utils.ErrorResponse(c, http.StatusNotFound, "host not found")
        return
    }
    
    // Clear fingerprint
    if err := h.db.Model(&host).Update("fingerprint", "").Error; err != nil {
        utils.ErrorResponse(c, http.StatusInternalServerError, "failed to reset fingerprint")
        return
    }
    
    // Log security event
    models.SecurityEventLog(h.db, models.ConfigChanged, models.SeverityLow,
        userID, middleware.GetUsername(c), c.ClientIP(), c.Request.UserAgent(),
        "Reset SSH host fingerprint for "+host.Name,
        map[string]interface{}{
            "host_id":   host.ID,
            "host_name": host.Name,
        })
    
    utils.SuccessResponse(c, http.StatusOK, gin.H{
        "message": "fingerprint reset successfully, will be updated on next connection",
    })
}
```

#### 前端实现

```vue
<!-- web/src/views/ssh/HostList.vue -->
<template>
  <a-button 
    @click="resetFingerprint(host.id)"
    title="重装系统后重置指纹"
    icon="reload"
  >
    重置指纹
  </a-button>
</template>

<script>
export default {
  methods: {
    async resetFingerprint(hostId) {
      try {
        await this.$api.sshHosts.resetFingerprint(hostId)
        this.$message.success('指纹已重置，下次连接时自动更新')
      } catch (error) {
        this.$message.error('重置失败：' + error.message)
      }
    }
  }
}
</script>
```

---

### 方案 3: 命令行工具（运维友好）

创建命令行工具供管理员使用。

```go
// cmd/reset_fingerprint.go

package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/ihxw/termiscope/internal/database"
	"github.com/ihxw/termiscope/internal/models"
	"gorm.io/gorm"
)

func main() {
	hostID := flag.Uint("id", 0, "Host ID to reset fingerprint")
	hostName := flag.String("name", "", "Host name to reset fingerprint")
	resetAll := flag.Bool("all", false, "Reset all host fingerprints")
	flag.Parse()

	db, err := database.InitDB("data/termiscope.db")
	if err != nil {
		log.Fatalf("初始化数据库失败：%v", err)
	}

	if *resetAll {
		if err := db.Model(&models.SSHHost{}).Update("fingerprint", "").Error; err != nil {
			log.Fatalf("批量重置失败：%v", err)
		}
		fmt.Println("✅ 已重置所有主机的指纹")
		return
	}

	if *hostID > 0 {
		if err := resetHost(db, *hostID, ""); err != nil {
			log.Fatalf("重置失败：%v", err)
		}
		return
	}

	if *hostName != "" {
		var host models.SSHHost
		if err := db.Where("name = ?", *hostName).First(&host).Error; err != nil {
			log.Fatalf("未找到主机：%s", *hostName)
		}
		if err := resetHost(db, host.ID, host.Name); err != nil {
			log.Fatalf("重置失败：%v", err)
		}
		return
	}

	fmt.Println("使用方法:")
	fmt.Println("  reset_fingerprint -id=123     # 按 ID 重置")
	fmt.Println("  reset_fingerprint -name=host  # 按名称重置")
	fmt.Println("  reset_fingerprint -all        # 重置所有")
	os.Exit(1)
}

func resetHost(db *gorm.DB, hostID uint, hostName string) error {
	if err := db.Model(&models.SSHHost{}).Where("id = ?", hostID).Update("fingerprint", "").Error; err != nil {
		return err
	}
	
	name := hostName
	if name == "" {
		name = fmt.Sprintf("ID=%d", hostID)
	}
	fmt.Printf("✅ 已重置主机 %s 的指纹\n", name)
	return nil
}
```

**使用示例**:
```bash
# 按 ID 重置
go run cmd/reset_fingerprint.go -id=123

# 按名称重置
go run cmd/reset_fingerprint.go -name=my-vps

# 重置所有
go run cmd/reset_fingerprint.go -all
```

---

### 方案 4: 自动检测 + 用户确认（智能化）

在检测到指纹不匹配时，提供友好的提示和自助重置选项。

```go
// internal/utils/ssh_verify.go 修改

// HostKeyCallback returns an ssh.HostKeyCallback for TOFU verification
func (v *SSHKeyVerifier) HostKeyCallback() ssh.HostKeyCallback {
	return func(hostname string, remote net.Addr, key ssh.PublicKey) error {
		fingerprint := ssh.FingerprintSHA256(key)

		if v.savedFingerprint != "" {
			if fingerprint != v.savedFingerprint {
				// 记录安全事件
				logSecurityEvent(v.db, SSHHostKeyMismatch, SeverityCritical,
					v.hostID, "", "", "",
					fmt.Sprintf("主机密钥指纹不匹配！期望：%s, 实际：%s", v.savedFingerprint, fingerprint),
					map[string]interface{}{
						"host_id":     v.hostID,
						"expected_fp": v.savedFingerprint,
						"actual_fp":   fingerprint,
						"remote_addr": remote.String(),
						"hostname":    hostname,
					})

				// 返回详细错误信息，包含重置指引
				return fmt.Errorf("⚠️ 主机密钥指纹不匹配！可能的原因:\n"+
					"1. 中间人攻击（危险！）\n"+
					"2. VPS 重装了系统（安全）\n"+
					"3. SSH 服务重新安装（安全）\n\n"+
					"如果是 VPS 重装系统，请通过以下方式重置指纹:\n"+
					"- Web 界面：编辑主机 -> 点击'重置指纹'\n"+
					"- 数据库：UPDATE ssh_hosts SET fingerprint='' WHERE id=%d\n"+
					"- 命令行：go run cmd/reset_fingerprint.go -id=%d\n\n"+
					"期望的指纹：%s\n"+
					"实际的指纹：%s",
					v.hostID, v.hostID, v.savedFingerprint, fingerprint)
			}
			return nil
		}

		// First time connection - save fingerprint (TOFU)
		if v.onNewFingerprint != nil {
			if err := v.onNewFingerprint(fingerprint); err != nil {
				return fmt.Errorf("保存主机密钥指纹失败：%w", err)
			}
			// 记录新主机密钥保存事件
			logSecurityEvent(v.db, "LOGIN_SUCCESS", "LOW",
				v.hostID, "", "", "",
				fmt.Sprintf("首次连接并保存主机密钥指纹：%s", fingerprint),
				map[string]interface{}{
					"host_id":     v.hostID,
					"fingerprint": fingerprint,
					"remote_addr": remote.String(),
				})
		}

		return nil
	}
}
```

---

## 最佳实践建议

### 1. 预防措施

**备份指纹**:
```bash
# 导出主机指纹备份
sqlite3 data/termiscope.db "SELECT id, name, fingerprint FROM ssh_hosts;" > fingerprints_backup.txt
```

**记录系统信息**:
```go
// 在保存指纹时同时记录其他信息
type SSHHost struct {
    // ... existing fields ...
    LastFingerprintUpdate time.Time  `json:"last_fingerprint_update"`
    OSInstallDate         time.Time  `json:"os_install_date"`  // 系统安装日期
}
```

### 2. 检测系统重装

```go
// 自动检测可能的系统重装
func DetectPossibleOSReinstall(db *gorm.DB, hostID uint, newFingerprint string) bool {
    var host models.SSHHost
    db.First(&host, hostID)
    
    // 如果指纹在短时间内多次变化，可能是测试环境或频繁重装
    var changeCount int64
    db.Model(&models.SecurityEvent{}).
        Where("host_id = ? AND event_type = 'SSH_HOST_KEY_MISMATCH'", hostID).
        Where("created_at > ?", time.Now().Add(-24*time.Hour)).
        Count(&changeCount)
    
    return changeCount > 3  // 24 小时内变化超过 3 次
}
```

### 3. 监控和告警

```go
// 监控指纹变化频率
func MonitorFingerprintChanges(db *gorm.DB) {
    var hosts []models.SSHHost
    db.Find(&hosts)
    
    for _, host := range hosts {
        var changeCount int64
        db.Model(&models.SecurityEvent{}).
            Where("host_id = ? AND event_type = 'SSH_HOST_KEY_MISMATCH'", host.ID).
            Where("created_at > ?", time.Now().Add(-7*24*time.Hour)).
            Count(&changeCount)
        
        if changeCount > 5 {
            // 一周内变化 5 次以上，发送告警
            log.Printf("⚠️ 警告：主机 %s 一周内指纹变化 %d 次，可能存在异常", host.Name, changeCount)
        }
    }
}
```

---

## 完整工作流程

### 用户视角

1. **VPS 重装系统**
2. **尝试连接** → 收到指纹不匹配错误
3. **查看错误信息** → 包含详细的重置指引
4. **选择重置方式**:
   - Web 界面点击"重置指纹"按钮
   - 或运行命令行工具
   - 或联系管理员执行 SQL
5. **重置成功** → 数据库指纹清空
6. **重新连接** → 自动保存新指纹
7. **正常使用** ✅

### 系统视角

```
用户连接 
  ↓
检查指纹 
  ↓
指纹不匹配 
  ↓
拒绝连接 + 返回详细错误（包含重置指引）
  ↓
用户重置指纹（数据库清空）
  ↓
用户重新连接
  ↓
TOFU: 自动保存新指纹
  ↓
连接成功 + 记录安全事件
```

---

## 安全注意事项

### ✅ 推荐做法

1. **记录所有指纹重置操作**
   ```go
   models.SecurityEventLog(db, models.ConfigChanged, models.SeverityLow, ...)
   ```

2. **需要用户确认**
   ```vue
   <a-modal title="确认重置指纹" okText="确认" cancelText="取消">
     <p>确定要重置主机 "{{ host.name }}" 的指纹吗？</p>
     <p class="warn">仅当您确认 VPS 重装了系统时才执行此操作！</p>
   </a-modal>
   ```

3. **限制重置频率**
   ```go
   // 24 小时内只允许重置 3 次
   func CanResetFingerprint(db *gorm.DB, userID uint, hostID uint) bool {
       var count int64
       db.Model(&models.SecurityEvent{}).
           Where("user_id = ? AND details LIKE '%reset fingerprint%'", userID).
           Where("created_at > ?", time.Now().Add(-24*time.Hour)).
           Count(&count)
       return count < 3
   }
   ```

### ❌ 不推荐做法

1. **不要完全禁用指纹验证**
   ```go
   // ❌ 危险！不要这样做
   HostKeyCallback: ssh.InsecureIgnoreHostKey()
   ```

2. **不要自动接受新指纹**
   ```go
   // ❌ 危险！不要自动覆盖
   if fingerprint != savedFingerprint {
       db.Save(&host, "fingerprint", fingerprint)  // 不要这样做！
   }
   ```

3. **不要忽略告警**
   ```go
   // ❌ 即使记录了也要告警
   if fingerprint != savedFingerprint {
       // 仅记录日志，不告警  // 不要这样做！
   }
   ```

---

## 故障排除

### 问题 1: 重置后仍然无法连接

**检查**:
```sql
-- 确认指纹已清空
SELECT id, name, fingerprint FROM ssh_hosts WHERE id = ?;
```

**解决**: 确保数据库事务已提交，重启应用

### 问题 2: 频繁出现指纹不匹配

**可能原因**: 
- 测试环境频繁重装系统
- 有攻击者尝试中间人攻击

**解决方法**:
```go
// 启用严格模式
if DetectPossibleOSReinstall(db, hostID, newFingerprint) {
    log.Printf("🚠 主机 %s 频繁更换指纹，可能存在安全风险", host.Name)
    // 发送高优先级告警
    models.SecurityEventLog(db, models.SuspiciousActivity, models.SeverityHigh, ...)
}
```

### 问题 3: 批量重置需求

**场景**: 迁移服务器集群

**解决**:
```bash
# 导出所有主机
sqlite3 data/termiscope.db "SELECT id, name FROM ssh_hosts;" > hosts.txt

# 批量重置
while read id name; do
    echo "重置 $name (ID=$id)"
    go run cmd/reset_fingerprint.go -id=$id
done < hosts.txt
```

---

## 总结

**标准流程**（推荐所有用户）:
1. VPS 重装系统
2. 连接失败，查看详细错误
3. Web 界面点击"重置指纹"
4. 重新连接，自动保存新指纹
5. 完成 ✅

**安全保证**:
- ✅ 所有重置操作都有审计日志
- ✅ 需要用户主动确认
- ✅ 防止自动覆盖（避免被攻击）
- ✅ 提供多种重置方式

**用户体验**:
- 错误信息清晰，包含解决步骤
- Web 界面一键重置
- 命令行工具供高级用户使用
- API 可供集成

---

**文档版本**: 1.0  
**最后更新**: 2026-03-19  
**适用版本**: TermiScope v1.0+
