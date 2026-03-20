# SSH 指纹更新简化方案

## 问题

VPS 重装系统后 SSH 主机密钥会改变，导致无法连接。

## 解决方案

### 当前实现（简化版）

**流程**：
1. 用户尝试连接 SSH
2. 检测到指纹不匹配
3. **前端弹出确认对话框**：
   ```
   ⚠️ 远程主机身份标识已更改！
   
   这可能是：
   - VPS 重装了系统（安全）
   - SSH 服务重新安装（安全）
   - 中间人攻击（危险！）
   
   新指纹：SHA256:xyz789...
   旧指纹：SHA256:abc123...
   
   [取消连接]  [确认更新并继续]
   ```
4. 用户点击"确认更新"
5. 自动保存新指纹到数据库
6. 连接成功 ✅

### 技术实现

#### 后端逻辑

**文件**: `internal/handlers/ssh_ws.go`

```go
// 1. 检查是否需要更新指纹
if c.Query("update_fingerprint") == "true" {
    newFp := c.Query("fingerprint")
    host.Fingerprint = newFp
    h.db.Save(&host)
    
    // 记录安全事件
    models.SecurityEventLog(...)
}

// 2. 连接时检测指纹不匹配
if err := sshClient.Connect(); err != nil {
    if strings.Contains(err.Error(), "fingerprint mismatch") {
        // 返回错误和新指纹给前端
        ws.WriteJSON(gin.H{
            "type": "error",
            "code": "fingerprint_mismatch",
            "data": "远程主机身份标识已更改...",
            "meta": gin.H{
                "new_fingerprint": newFp,
                "host_id": host.ID,
                "action": "confirm_update",
            },
        })
    }
}
```

#### 前端逻辑（需要实现）

**文件**: `web/src/views/ssh/Terminal.vue`

```javascript
// WebSocket 消息处理
ws.onmessage = (event) => {
    const msg = JSON.parse(event.data)
    
    if (msg.code === 'fingerprint_mismatch') {
        // 弹出确认对话框
        Modal.confirm({
            title: '⚠️ 远程主机身份标识已更改',
            content: `
                <p>${msg.data}</p>
                <p><strong>新指纹：</strong>${msg.meta.new_fingerprint}</p>
                <p class="warning">如果是 VPS 重装了系统，请点击"确认"更新指纹</p>
            `,
            onOk: () => {
                // 用户确认，更新指纹并重新连接
                const newTicket = await getWSTicket()
                const wsUrl = `/api/ssh/${hostId}?ticket=${newTicket}&update_fingerprint=true&fingerprint=${msg.meta.new_fingerprint}`
                connectWebSocket(wsUrl)
            },
            cancelText: '取消',
            okText: '确认更新',
        })
    }
}
```

---

## 工作流程图

```
用户点击连接
     ↓
建立 WebSocket 连接
     ↓
SSH 客户端连接远程主机
     ↓
检查指纹匹配？
    ├─ 是 → 连接成功 ✅
    └─ 否
        ↓
返回错误给前端（包含新指纹）
        ↓
前端弹出确认对话框
        ↓
用户选择？
    ├─ 取消 → 断开连接
    └─ 确认
        ↓
重新连接（带 update_fingerprint=true）
        ↓
后端保存新指纹
        ↓
连接成功 ✅
```

---

## 安全保证

### ✅ 安全措施

1. **用户必须手动确认**
   - 不能自动覆盖指纹
   - 防止中间人攻击

2. **详细的警告信息**
   - 告知用户可能的风险
   - 提供新旧指纹对比

3. **审计日志记录**
   ```go
   models.SecurityEventLog(
       ConfigChanged,
       SeverityLow,
       "Updated SSH host fingerprint",
       metadata,
   )
   ```

4. **仅所有者能更新**
   - 通过用户 ID 和主机 ID 验证权限
   - 防止越权操作

### ❌ 不推荐的做法

```go
// ❌ 危险：不要自动接受新指纹
if fp != cfg.Fingerprint {
    db.Save(&host, "fingerprint", fp)  // 不要这样做！
}

// ✅ 正确：让用户确认后再更新
```

---

## 用户体验优化

### 前端提示优化

```vue
<template>
  <a-modal
    v-model:visible="showFingerprintModal"
    title="⚠️ 主机密钥变更"
    okText="确认更新"
    cancelText="取消"
    @ok="confirmUpdate"
  >
    <div class="warning-box">
      <a-alert
        message="检测到远程主机密钥变更"
        description="这通常发生在 VPS 重装系统后。如果您确认是这种情况，请点击"确认更新"。"
        type="warning"
        show-icon
      />
      
      <div class="fingerprint-compare">
        <div class="old-fp">
          <strong>旧指纹:</strong>
          <code>{{ oldFingerprint }}</code>
        </div>
        <div class="arrow">↓</div>
        <div class="new-fp">
          <strong>新指纹:</strong>
          <code>{{ newFingerprint }}</code>
        </div>
      </div>
      
      <a-checkbox v-model:checked="confirmCheckbox">
        我确认这是 VPS 重装系统导致的变化
      </a-checkbox>
    </div>
  </a-modal>
</template>

<script>
export default {
  data() {
    return {
      showFingerprintModal: false,
      oldFingerprint: '',
      newFingerprint: '',
      confirmCheckbox: false,
    }
  },
  methods: {
    async confirmUpdate() {
      if (!this.confirmCheckbox) {
        this.$message.warning('请先确认是 VPS 重装系统')
        return
      }
      
      // 更新指纹并重新连接
      await this.connectWithNewFingerprint()
      this.$message.success('指纹已更新，连接成功')
    },
  },
}
</script>

<style scoped>
.warning-box {
  padding: 20px;
}
.fingerprint-compare {
  margin: 20px 0;
  text-align: center;
}
.old-fp, .new-fp {
  margin: 10px 0;
  padding: 10px;
  background: #f5f5f5;
  border-radius: 4px;
}
.new-fp {
  background: #e6f7ff;
  border: 1px solid #1890ff;
}
.arrow {
  font-size: 24px;
  color: #1890ff;
}
code {
  display: block;
  margin-top: 5px;
  padding: 5px;
  background: #fff;
  font-family: 'Courier New', monospace;
  word-break: break-all;
}
</style>
```

---

## 优势对比

### 之前的复杂方案 ❌

- 需要手动执行 SQL
- 或运行命令行工具
- 或多步骤操作
- 用户体验差

### 现在的简化方案 ✅

- Web 界面一键确认
- 自动更新指纹
- 实时反馈
- 用户友好

---

## 测试验证

### 测试步骤

1. **准备环境**
   ```bash
   # 记录当前指纹
   sqlite3 data/termiscope.db "SELECT id, name, fingerprint FROM ssh_hosts WHERE id=1;"
   ```

2. **模拟指纹变化**
   ```sql
   -- 手动修改指纹（模拟 VPS 重装）
   UPDATE ssh_hosts 
   SET fingerprint = 'SHA256:old_fake_fingerprint' 
   WHERE id = 1;
   ```

3. **测试连接**
   - Web 界面点击连接
   - 应该弹出确认对话框
   - 点击"确认更新"
   - 连接成功

4. **验证结果**
   ```sql
   -- 检查指纹已更新
   SELECT fingerprint FROM ssh_hosts WHERE id = 1;
   -- 应该是新的正确指纹
   ```

---

## 常见问题

### Q1: 如果用户误点了确认怎么办？

**A**: 可以在主机管理界面手动修改指纹，或删除后重新连接（会触发 TOFU）

### Q2: 是否需要限制更新频率？

**A**: 暂时不需要，因为每次更新都需要用户手动确认。如果有异常，审计日志会记录。

### Q3: 支持批量更新吗？

**A**: 当前不支持。如果需要批量更新，可以添加"批量确认"功能。

---

## 总结

### 核心改进

✅ **简单**: 用户只需点击一次确认  
✅ **直观**: 清晰的警告和指纹对比  
✅ **安全**: 必须手动确认，防止自动攻击  
✅ **可追溯**: 完整的审计日志  

### 实现状态

- ✅ 后端逻辑完成
- ✅ WebSocket 消息处理完成
- ⏳ 前端 UI 待实现
- ✅ 安全审计完成

---

**文档版本**: 1.0 (简化版)  
**最后更新**: 2026-03-19  
**状态**: 已实现，待前端集成
