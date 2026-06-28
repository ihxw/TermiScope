# Project: TermiScope Improvement and Optimization

## Architecture
TermiScope 是一个基于 Go（后端）和 Vue 3 / Ant Design Vue（前端）的服务器管理平台。
- **后端 (Go)**:
  - `cmd/server/main.go`: 服务端入口，配置路由与中间件。
  - `internal/handlers/`: API 接口层，包括 `ssh_host.go` (主机管理与排序)、`sftp.go` (SFTP 文件上传/进度)、`ssh_ws.go` (SSH WebSocket 终端)。
  - `internal/models/`: 数据模型层，使用 GORM。主机模型定义在 `ssh_host.go` 中。
- **前端 (Vue 3 / Vite)**:
  - `web/src/views/HostManagement.vue`: 主机管理仪表盘，包含主机卡片渲染与拖拽排序。
  - `web/src/components/SftpBrowser.vue`: SFTP 文件浏览器与上传进度浮窗。
  - `web/src/api/`: 前端 API 封装，与后端 RESTful API 及 WebSocket 通信。

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Backend Reliability Fixes | 修复 Bug 3 (SFTP 传输无法中止/未监听 Context 取消) 与 Bug 4 (SSH WS 无缓冲 Channel 造成的 Goroutine 泄露) | None | PLANNED |
| 2 | Host Drag-Sorting Persistence | 修复 Bug 1 (拖拽排序与快速过滤/搜索的索引冲突)，并实现主机卡片拖拽排序在数据库/前端 LocalStorage 中的持久化存储 | M1 | PLANNED |
| 3 | SFTP Direct-Stream Upload UI | 修复 Bug 2 (并发上传冲突弹窗挂起)，实现非阻塞流式上传 UI，按目标主机分组并实时展示上传进度，无中间临时文件 | M2 | PLANNED |
| 4 | Final E2E Test & Coverage Hardening | 集成 E2E 测试轨道所完成的测试套件，并通过 Adversarial Testing (Challenger 攻击) 强化测试覆盖率 | M3 | PLANNED |

## Interface Contracts
### 1. 主机重新排序接口 (Reorder)
- **路径**: `PUT /api/ssh-hosts/reorder`
- **请求格式**: `{ "DeviceIds": [1, 2, 3] }` (主机 ID 数组)
- **响应格式**: `{ "code": 0, "message": "Success" }`
- **错误处理**: 事务更新失败时返回 `500`。如果拖拽时有主机过滤，前端应合并提交完整排序，避免数据重叠。

### 2. SFTP 文件直传与进度查询接口
- **直传路径**: `POST /api/sftp/upload/:hostId`
- **直传请求**: `multipart/form-data` 形式，包括 `file`、`remotePath`、`uploadId` 等参数。
- **直传响应**: 返回上传事务 ID 等。
- **进度查询路径**: `GET /api/sftp/upload-progress/:uploadId`
- **进度查询响应**: `{ "uploadId": "xxx", "percent": 85, "speed": 102400, "bytesTransferred": 850000, "completed": false, "error": "" }`

## Code Layout
- `cmd/server/main.go` - 后端主入口
- `internal/handlers/` - 后端 API 控制器
- `internal/models/` - 数据库 GORM 模型定义
- `web/src/views/HostManagement.vue` - 主机管理仪表盘组件
- `web/src/components/SftpBrowser.vue` - SFTP 浏览器与上传进度组件
- `web/src/api/` - 前端请求模块
