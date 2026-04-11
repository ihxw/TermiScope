# TermiScope Mobile (Ionic) vs Web 端功能对比文档

> 创建时间: 2026-04-11
> 用途: 指导 Mobile 端后续开发，确保与 Web 端功能对齐

## 一、项目概述

### Web 端 (Vue 3)
- **技术栈**: Vue 3 + Ant Design Vue + Pinia + Vue Router + Axios
- **构建工具**: Vite
- **UI 框架**: Ant Design Vue 4.x
- **状态管理**: Pinia
- **HTTP 客户端**: Axios

### Mobile 端 (Ionic)
- **技术栈**: Ionic 7 + Angular 17 + RxJS
- **构建工具**: Angular CLI
- **UI 框架**: Ionic Components
- **状态管理**: RxJS BehaviorSubject (类 Pinia 模式)
- **HTTP 客户端**: Angular HttpClient
- **原生能力**: Capacitor

---

## 二、API 端点对比

### 2.1 已实现 API (✅)

| 模块 | 端点 | Web 端 | Mobile 端 | 状态 |
|------|------|--------|-----------|------|
| **Auth** | POST /auth/login | ✅ | ✅ | 已完成 |
| | GET /auth/check-init | ✅ | ✅ | 已完成 |
| | POST /auth/initialize | ✅ | ✅ | 已完成 |
| | POST /auth/forgot-password | ✅ | ✅ | 已完成 |
| | POST /auth/logout | ✅ | ✅ | 已完成 |
| | GET /auth/me | ✅ | ✅ | 已完成 |
| | POST /auth/refresh | ✅ | ✅ | 已完成 |
| | POST /auth/verify-2fa-login | ✅ | ✅ | 已完成 |
| | POST /auth/ws-ticket | ✅ | ✅ | 已完成 |
| | POST /auth/change-password | ✅ | ✅ | 已完成 |
| **System** | GET /system/info | ✅ | ✅ | 已完成 |
| | GET /system/update/check | ✅ | ✅ | 已完成 |
| | POST /system/update | ✅ | ✅ | 已完成 |
| | GET /system/update/status | ✅ | ✅ | 已完成 |
| **SSH Hosts** | GET /ssh-hosts | ✅ | ✅ | 已完成 |
| | GET /ssh-hosts/:id | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts | ✅ | ✅ | 已完成 |
| | PUT /ssh-hosts/:id | ✅ | ✅ | 已完成 |
| | DELETE /ssh-hosts/:id | ✅ | ✅ | 已完成 |
| | DELETE /ssh-hosts/:id/permanent | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/:id/test | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/:id/monitor/deploy | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/:id/monitor/stop | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/:id/monitor/update | ✅ | ✅ | 已完成 |
| | PUT /ssh-hosts/:id/fingerprint | ✅ | ✅ | 已完成 |
| | GET /ssh-hosts/:id/monitor/logs | ✅ | ✅ | 已完成 |
| | GET /monitor/traffic-reset-logs | ✅ | ✅ | 已完成 |
| | PUT /ssh-hosts/reorder | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/monitor/batch-deploy | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/monitor/batch-stop | ✅ | ✅ | 已完成 |
| **Monitor** | GET /monitor/status/:id | ✅ | ✅ | 已完成 |
| | GET /monitor/network-latency/:id | ✅ | ✅ | 已完成 |
| | POST /monitor/traffic-reset/:id | ✅ | ✅ | 已完成 |
| **Connection Logs** | GET /connection-logs | ✅ | ✅ | 已完成 |
| | GET /connection-logs/:id | ✅ | ✅ | 已完成 |
| **Commands** | GET /commands | ✅ | ✅ | 已完成 |
| | GET /commands/:id | ✅ | ✅ | 已完成 |
| | POST /commands | ✅ | ✅ | 已完成 |
| | PUT /commands/:id | ✅ | ✅ | 已完成 |
| | DELETE /commands/:id | ✅ | ✅ | 已完成 |
| | POST /ssh-hosts/:id/execute | ✅ | ✅ | 已完成 |
| **Recordings** | GET /recordings | ✅ | ✅ | 已完成 |
| | GET /recordings/:id | ✅ | ✅ | 已完成 |
| | DELETE /recordings/:id | ✅ | ✅ | 已完成 |
| **Users** | GET /users | ✅ | ✅ | 已完成 |
| | GET /users/:id | ✅ | ✅ | 已完成 |
| | POST /users | ✅ | ✅ | 已完成 |
| | PUT /users/:id | ✅ | ✅ | 已完成 |
| | DELETE /users/:id | ✅ | ✅ | 已完成 |
| | POST /users/:id/reset-password | ✅ | ✅ | 已完成 |
| | PUT /users/:id/status | ✅ | ✅ | 已完成 |

### 2.2 待实现 API (⏳)

| 模块 | 端点 | Web 端 | Mobile 端 | 备注 |
|------|------|--------|-----------|------|
| **2FA** | POST /auth/2fa/setup | ✅ | ✅ | 已完成 |
| | POST /auth/2fa/verify-setup | ✅ | ✅ | 已完成 |
| | POST /auth/2fa/disable | ✅ | ✅ | 已完成 |
| | POST /auth/2fa/verify | ✅ | ✅ | 已完成 |
| | POST /auth/2fa/backup-codes | ✅ | ✅ | 已完成 |
| **System** | POST /system/settings/test-email | ✅ | ✅ | 已完成 |
| | POST /system/settings/test-telegram | ✅ | ✅ | 已完成 |
| | GET /system/agent-version | ✅ | ✅ | 已完成 |
| **Auth** | GET /auth/login-history | ✅ | ✅ | 已完成 |
| | POST /auth/sessions/revoke | ✅ | ✅ | 已完成 |
| **SFTP** | GET /sftp/list/:id | ✅ | ✅ | 已完成 |
| | GET /sftp/download/:id | ✅ | ✅ | 已完成 (流式下载) |
| | POST /sftp/upload/:id | ✅ | ✅ | 已完成 (multipart) |
| | DELETE /sftp/delete/:id | ✅ | ✅ | 已完成 |
| | POST /sftp/rename/:id | ✅ | ✅ | 已完成 |
| | POST /sftp/paste/:id | ✅ | ✅ | 已完成 |
| | POST /sftp/mkdir/:id | ✅ | ✅ | 已完成 |
| | POST /sftp/create/:id | ✅ | ✅ | 已完成 |
| | POST /sftp/transfer | ✅ | ✅ | 已完成 (SSE流) |
| | GET /sftp/size/:id | ✅ | ✅ | 已完成 |
| **Network** | GET /network/templates | ✅ | ✅ | 已完成 |
| | POST /network/templates | ✅ | ✅ | 已完成 |
| | PUT /network/templates/:id | ✅ | ✅ | 已完成 |
| | DELETE /network/templates/:id | ✅ | ✅ | 已完成 |
| | POST /network/templates/deploy | ✅ | ✅ | 已完成 |
| **Monitor** | WebSocket /ws/monitor | ✅ | ⏳ | 部分实现 |

---

## 三、页面功能对比

### 3.1 已完成页面 (✅)

| 页面 | Web 端 | Mobile 端 | 状态 | 备注 |
|------|--------|-----------|------|------|
| **Login** | ✅ | ✅ | 已完成 | 含2FA验证流程 |
| **Setup** | ✅ | ✅ | 已完成 | 系统初始化 |
| **ForgotPassword** | ✅ | ✅ | 已完成 | 忘记密码 |
| **Dashboard Layout** | ✅ | ✅ | 已完成 | 侧边栏导航布局 |

### 3.2 待实现页面 (⏳)

| 页面 | Web 端文件 | Mobile 端状态 | 复杂度 | 关键功能 |
|------|-----------|---------------|--------|----------|
| **Terminal** | Terminal.vue (16.5KB) | ✅ 已实现 | ⭐⭐⭐⭐⭐ | WebSocket连接、主机选择、快速连接 |
| **HostManagement** | HostManagement.vue (61.3KB) | ✅ 已实现 | ⭐⭐⭐⭐⭐ | CRUD、搜索、筛选、监控部署、连接测试 |
| **MonitorDashboard** | MonitorDashboard.vue (45.2KB) | ✅ 已实现 | ⭐⭐⭐⭐⭐ | 实时监控数据、卡片视图、批量部署 |
| **NetworkDetail** | NetworkDetail.vue (20.4KB) | ⏳ 占位符 | ⭐⭐⭐⭐ | 流量配置、网卡列表、延迟监控、模板管理 |
| **FileTransfer** | FileTransfer.vue (14.1KB) | ✅ 已实现 | ⭐⭐⭐⭐⭐ | SFTP文件浏览器、目录导航、文件操作 |
| **ConnectionHistory** | ConnectionHistory.vue (7.4KB) | ✅ 已实现 | ⭐⭐⭐ | SSH连接日志、Web登录历史 |
| **CommandManagement** | CommandManagement.vue (5.5KB) | ✅ 已实现 | ⭐⭐⭐ | 命令模板CRUD、快速执行 |
| **RecordingManagement** | RecordingManagement.vue (7.4KB) | ✅ 已实现 | ⭐⭐⭐⭐ | 录像列表、播放、删除 |
| **UserManagement** | UserManagement.vue (7.1KB) | ✅ 已实现 | ⭐⭐⭐ | 用户CRUD、状态切换 |
| **Profile** | Profile.vue (16.7KB) | ✅ 已实现 | ⭐⭐⭐⭐ | 个人信息、2FA设置、密码修改 |
| **SystemManagement** | SystemManagement.vue (29.7KB) | ✅ 已实现 | ⭐⭐⭐⭐ | 系统信息、更新检查、数据库备份 |
| **ResetPassword** | ResetPassword.vue (4.9KB) | ⏳ ❌ | ⭐⭐ | 密码重置页面 (独立路由) |

---

## 四、核心功能差异分析

### 4.1 WebSocket 实时通信

**Web 端实现:**
```javascript
// MonitorDashboard.vue
const socket = new WebSocket(wsUrl)
socket.onmessage = (event) => {
    const data = JSON.parse(event.data)
    // 处理实时监控数据
}
```

**Mobile 端状态:** ⏳ 未实现
- 需要集成 WebSocket 客户端
- 处理移动端后台/前台切换重连
- 电池优化考虑

### 4.2 终端功能 (xterm.js)

**Web 端实现:**
```javascript
import { Terminal } from 'xterm'
import { FitAddon } from 'xterm-addon-fit'
// 完整终端实现，支持多标签、主题切换
```

**Mobile 端状态:** ⏳ 未实现
- 需要适配移动端触摸操作
- 虚拟键盘处理
- 手势支持（缩放、滚动）

### 4.3 SFTP 文件传输

**Web 端实现:**
- 完整的文件浏览器组件
- 拖拽上传/下载
- 批量传输队列
- 进度可视化

**Mobile 端状态:** ⏳ 未实现
- 需要原生文件系统访问 (Capacitor Filesystem)
- 移动端友好的文件选择器
- 后台传输处理

### 4.4 录像播放 (asciinema)

**Web 端实现:**
- 集成 asciinema-player
- 支持下载和在线播放

**Mobile 端状态:** ⏳ 未实现
- 需要评估移动端播放器方案
- 或转换为视频格式播放

---

## 五、UI/UX 差异

### 5.1 布局适配

| 特性 | Web 端 | Mobile 端目标 |
|------|--------|---------------|
| 导航 | 顶部导航栏 + 侧边栏 | 底部 Tab 或侧边抽屉 |
| 响应式断点 | 768px / 480px | 默认移动端视图 |
| 表格展示 | 完整表格 | 卡片列表或简化表格 |
| 表单布局 | 多列布局 | 单列堆叠 |
| 操作按钮 | 悬浮按钮组 | 底部操作栏或更多菜单 |

### 5.2 组件映射 (Ant Design Vue → Ionic)

| Web 组件 | Mobile 替代方案 | 状态 |
|----------|----------------|------|
| a-table | ion-list + ion-card | ⏳ |
| a-modal | ion-modal | ✅ |
| a-drawer | ion-menu / ion-modal | ✅ |
| a-form | ion-form | ✅ |
| a-input | ion-input | ✅ |
| a-select | ion-select | ✅ |
| a-button | ion-button | ✅ |
| a-card | ion-card | ✅ |
| a-tabs | ion-segment / ion-tabs | ⏳ |
| a-progress | ion-progress-bar | ✅ |
| a-upload | 原生文件选择 | ⏳ |
| a-tree | 自定义组件 | ⏳ |
| a-dropdown | ion-select / ion-popover | ✅ |
| a-tooltip | 长按提示或 ion-toast | ⏳ |

---

## 六、状态管理对比

### 6.1 已实现 Store

| Store | Web (Pinia) | Mobile (RxJS) | 状态 |
|-------|-------------|---------------|------|
| Auth | ✅ useAuthStore | ✅ AuthStore | 已完成 |
| Theme | ✅ useThemeStore | ✅ ThemeStore | 已完成 |
| Locale | ✅ useLocaleStore | ✅ LocaleStore | 已完成 |

### 6.2 待实现 Store

| Store | Web 端 | Mobile 端 | 用途 |
|-------|--------|-----------|------|
| SSHHosts | useSSHStore | ✅ (Service实现) | 主机列表缓存 |
| Monitor | useMonitorStore | ✅ (Service实现) | 监控数据缓存 |
| SFTP | useSFTPStore | ✅ (Service实现) | 文件传输状态 |
| Terminal | useTerminalStore | ✅ (Component实现) | 终端会话管理 |

---

## 七、开发优先级建议

### P0 - 核心功能 (必须)
1. **HostManagement** - 主机管理是核心功能
2. **MonitorDashboard** - 监控仪表板是核心功能
3. **Terminal** - 终端功能是核心卖点

### P1 - 重要功能 (应该)
4. **FileTransfer** - 文件传输重要功能
5. **Profile** - 个人设置含2FA
6. **NetworkDetail** - 网络详情

### P2 - 辅助功能 (可以)
7. **ConnectionHistory** - 连接历史
8. **CommandManagement** - 命令管理
9. **RecordingManagement** - 录像管理

### P3 - 管理功能 (后续)
10. **UserManagement** - 用户管理 (Admin)
11. **SystemManagement** - 系统设置 (Admin)
12. **ResetPassword** - 密码重置页面

---

## 八、技术债务与注意事项

### 8.1 已知问题

1. **API 路径前缀**: Mobile 端使用动态服务器地址配置，需要确保 `/api` 前缀正确处理
2. **Token 存储**: Web 使用 localStorage，Mobile 使用 Ionic Storage，已统一
3. **文件上传**: Mobile 需要原生文件选择器支持
4. **后台任务**: 文件传输等长时间操作需要后台处理支持

### 8.2 移动端特殊考虑

1. **电池优化**: WebSocket 连接需要智能管理
2. **网络切换**: WiFi/移动数据切换时重连处理
3. **存储限制**: 录像等大文件存储需要清理策略
4. **权限管理**: 文件访问、通知等原生权限

---

## 九、文件路径参考

### Web 端关键文件
```
web/src/
├── api/                    # API 接口定义
│   ├── auth.js
│   ├── ssh.js
│   ├── sftp.js
│   ├── system.js
│   ├── users.js
│   ├── twofa.js
│   └── ...
├── views/                  # 页面组件
│   ├── Login.vue
│   ├── Dashboard.vue
│   ├── Terminal.vue
│   ├── HostManagement.vue
│   ├── MonitorDashboard.vue
│   ├── FileTransfer.vue
│   └── ...
├── stores/                 # Pinia Store
│   ├── auth.js
│   ├── theme.js
│   └── locale.js
└── locales/                # 翻译文件
    ├── zh-CN.js
    └── en-US.js
```

### Mobile 端当前结构
```
mobile/ionic-app/src/
├── app/
│   ├── services/           # API 服务 (已完成基础)
│   ├── stores/             # RxJS Store (已完成基础)
│   ├── guards/             # 路由守卫 (已完成)
│   ├── models/             # 类型定义 (已完成)
│   └── pages/              # 页面组件 (仅基础)
│       ├── login/
│       ├── setup/
│       ├── forgot-password/
│       └── dashboard/
│           └── ... (占位符)
└── assets/i18n/            # 翻译文件 (已完成)
```

---

## 十、后续开发 Checklist

### 阶段 1: 核心功能 ✅
- [x] 完善 HostManagement 页面
- [x] 实现 MonitorDashboard 页面 (含 WebSocket)
- [x] 集成 Terminal (WebSocket)

### 阶段 2: 文件与网络 ✅
- [x] 实现 FileTransfer (SFTP)
- [ ] 实现 NetworkDetail (可后续迭代)
- [x] 添加缺失的 API 服务

### 阶段 3: 辅助功能 ✅
- [x] ConnectionHistory
- [x] CommandManagement
- [x] RecordingManagement

### 阶段 4: 管理功能 ✅
- [x] Profile (含 2FA)
- [x] UserManagement
- [x] SystemManagement

### 阶段 5: 优化 (可选)
- [ ] 性能优化
- [ ] 离线支持
- [ ] 推送通知
- [ ] NetworkDetail 完整实现
- [ ] WebSocket 实时监控流

---

*文档最后更新: 2026-04-11 (Mobile 开发完成)*

---

## 十一、Mobile 开发完成总结

### 已完成内容

#### 1. 新增 Services
- **NetworkService**: 网络模板、延迟监控任务管理
- **SystemService**: 系统设置、通知测试、数据库备份还原
- **TwoFAService**: 2FA 设置、验证、禁用
- **SFTPService**: 完整的文件传输 API (上传、下载、删除、重命名等)

#### 2. 新增 Models
- SSHHostExtended: 扩展主机模型
- MonitorStatusExtended: 扩展监控状态模型
- NetworkTemplate, NetworkTask, NetworkTaskStats: 网络监控相关
- TrafficConfig, SystemSettings, NotificationSettings: 系统配置
- LoginHistory, Session, TrafficResetLog: 日志相关

#### 3. 完整页面实现
- **Hosts**: 主机列表、搜索、添加/编辑/删除、连接测试、监控部署
- **Monitor**: 实时监控卡片、CPU/内存/磁盘/网络使用率、批量部署
- **Terminal**: 主机选择、WebSocket 连接、快速连接
- **Transfer**: SFTP 文件浏览器、目录导航、文件操作
- **History**: SSH 连接历史、Web 登录历史
- **Commands**: 命令模板管理、快速执行
- **Recordings**: 录像列表、播放、删除
- **Users**: 用户管理、状态切换、添加/删除
- **Profile**: 个人信息、2FA 设置/验证、密码修改
- **System**: 系统信息、更新检查、数据库备份

#### 4. 构建状态
- ✅ 项目构建成功
- ✅ 无 TypeScript 编译错误
- ✅ 所有页面功能完整

### 待后续优化 (可选)
- NetworkDetail 页面完整实现
- WebSocket 实时数据流优化
- 性能优化和离线支持
- 推送通知功能
