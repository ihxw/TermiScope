# TermiScope Mobile 开发状态

更新时间：2026-06-13

## 当前决策

移动端正式主线切换为：

```text
mobile/flutter_app
```

旧的 `mobile/ionic-app` 已删除，不再作为维护目标。

详细架构和实时方案见：

```text
docs/MOBILE_APP_ARCHITECTURE_REALTIME_PLAN.md
```

## 技术方向

- Flutter 原生移动端。
- 当前过渡期继续使用已有 Provider/AppState。
- 后续逐步重构为 feature/controller/repository 分层。
- SSH 终端使用 Dart `xterm`。
- SSH 与监控实时流使用 `web_socket_channel`。
- SFTP 文件操作逐步接入原生文件选择、保存、分享和全局传输队列。

## 已完成

- 删除历史 Ionic/Angular 移动端目录。
- 保留并启用 `mobile/flutter_app` 作为唯一移动端主线。
- 拆分 Flutter App 入口：
  - `lib/main.dart`
  - `lib/app/termiscope_app.dart`
  - `lib/app/app_theme.dart`
- 新增共享实时 URL 构建：
  - `lib/core/realtime/realtime_url.dart`
- `TerminalService` 与 `MonitorService` 已使用共享 WebSocket URL 构建逻辑。
- 更新 `mobile/flutter_app/README.md`。

## 后续优先级

### P0

- 梳理认证与 token refresh。
- 建立 `core/api` HTTP client。
- 建立 secure storage 适配层。
- 重构终端 session controller。
- 重构监控实时流 controller。
- 重构 SFTP 浏览与传输队列。

### P1

- 多终端会话。
- 命令模板发送到终端。
- SFTP 上传/下载/跨主机传输进度。
- 监控详情页。
- Profile 与 2FA 管理。

### P2

- 录像播放。
- 用户管理。
- 系统管理。
- Agent 批量部署/升级。
- 网络监控任务与模板。

## 验证状态

本次环境没有安装 `flutter` 命令，因此未运行 Flutter 编译或测试。

已验证：

- Web 前端构建：`cd web && npm run build` 通过。
- 版本号 `1.6.20` 已提交并推送到远程 `main`。
