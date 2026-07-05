# TermiScope 移动端应用架构与实时方案

更新时间：2026-06-13

## 1. 结论

在**不考虑复用 Web 端代码**的前提下，建议移动端正式主线采用：

**Flutter + Riverpod + GoRouter + Dio + web_socket_channel + 原生插件**

这是当前项目更合适的移动端架构。理由：

- TermiScope 的移动端核心体验是 SSH 终端、实时监控、SFTP 文件操作、系统通知和移动端生命周期管理，这些更接近原生 App 能力，而不是 Web UI 适配。
- Flutter 对 Android/iOS 的交互一致性、性能、动画、触摸手势、键盘适配、横竖屏控制和离线缓存更可控。
- 终端交互可以使用 Dart `xterm` 包，避免在移动端 WebView 内调 xterm.js 带来的键盘、选择、滚动和输入法兼容问题。
- SFTP 下载、上传、分享、文件选择、后台任务、系统通知、生物识别等能力更适合通过 Flutter 原生插件实现。
- 现有 `mobile/flutter_app` 已有服务、终端、监控、页面雏形，可以作为主线重构基础；`mobile/ionic-app` 作为历史参考冻结。

推荐目录：

```text
mobile/
  flutter_app/                 # 正式移动端主线，重构为生产架构
  ionic-app/                   # 冻结，仅作为功能和文案参考
```

## 2. 当前项目移动端依赖的后端能力

后端已经具备移动端所需的核心接口：

- 认证：`/api/auth/login`、`/api/auth/refresh`、`/api/auth/ws-ticket`、2FA、初始化、登出。
- SSH 终端 WebSocket：`GET /api/ws/ssh/:hostId?ticket=...`。
- 监控 WebSocket：`GET /api/monitor/stream?token=...`。
- SFTP：列表、上传、下载、删除、重命名、复制/移动、新建目录/文件、跨主机传输、上传进度。
- 录像：`GET /api/recordings/:id/stream`。
- 运维管理：主机、Agent 部署、命令模板、连接历史、用户、系统设置、网络监控任务。

移动端不需要复制 Web 页面形态。应围绕移动设备重新组织信息架构：

- 首页优先显示主机状态、告警、最近连接。
- 终端优先支持横屏、虚拟功能键、复制粘贴、命令模板。
- SFTP 优先支持文件选择、分享、保存到本机、传输队列。
- 管理类功能压缩到二级页面，避免占用主导航。

## 3. 推荐技术栈

### 3.1 Flutter 核心依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.x
  go_router: ^14.x
  dio: ^5.x
  web_socket_channel: ^3.x
  xterm: ^4.x
  shared_preferences: ^2.x
  flutter_secure_storage: ^9.x
  connectivity_plus: ^6.x
  file_picker: ^8.x
  path_provider: ^2.x
  share_plus: ^10.x
  permission_handler: ^11.x
  local_auth: ^2.x
  flutter_local_notifications: ^17.x
  intl: ^0.19.x
```

### 3.2 状态与路由

- 状态管理：Riverpod。
- 路由：GoRouter。
- HTTP：Dio，统一拦截 401、refresh token、错误格式。
- WebSocket：封装 `RealtimeManager`，页面不直接创建 socket。
- 安全存储：`flutter_secure_storage` 存 token、refresh token、服务器地址、可选生物识别开关。
- 普通偏好：`shared_preferences` 存主题、语言、终端字体、最近主机。

## 4. 推荐目录结构

```text
mobile/flutter_app/lib/
  main.dart
  app/
    termiscope_app.dart
    router.dart
    lifecycle.dart
    theme.dart
  core/
    api/
      api_client.dart
      api_exception.dart
      auth_interceptor.dart
      endpoints.dart
    realtime/
      realtime_manager.dart
      ws_connection.dart
      reconnect_policy.dart
      monitor_stream.dart
      terminal_channel.dart
    storage/
      secure_store.dart
      preferences_store.dart
    native/
      file_service.dart
      notification_service.dart
      biometric_service.dart
      network_service.dart
    models/
    utils/
  features/
    auth/
    home/
    hosts/
    monitor/
    terminal/
    sftp/
    transfer_queue/
    recordings/
    commands/
    profile/
    users/
    system/
    network/
  shared/
    widgets/
    layouts/
    empty_states/
    dialogs/
```

规则：

- `core/` 只放通用能力，不依赖具体页面。
- `features/` 按业务垂直切分，每个 feature 内部包含 page、controller、state、repository。
- 页面只消费 controller/state，不直接调用 Dio 或 WebSocket。
- 所有长连接和长任务都集中进入 `core/realtime` 或 `features/transfer_queue`。

## 5. 实时通信完整方案

### 5.1 统一 RealtimeManager

职责：

- 调 `/api/auth/ws-ticket` 获取一次性票据。
- 构建 `ws://` / `wss://` URL。
- 统一连接状态：`idle`、`connecting`、`open`、`reconnecting`、`closed`、`failed`。
- 指数退避重连：1s、2s、5s、10s、30s 上限。
- 监听 App 前后台：前台重连，后台关闭非必要连接。
- 监听网络变化：断网暂停重连，恢复后重新取票据连接。
- 处理 token refresh：HTTP token 刷新后，WebSocket 必须重新申请 ticket。

核心接口：

```dart
abstract class WsConnection {
  String get id;
  Stream<ConnectionState> get state;
  Future<void> connect();
  Future<void> disconnect([String? reason]);
  void send(Object data);
}
```

### 5.2 监控流

连接流程：

1. `POST /api/auth/ws-ticket`。
2. `GET /api/monitor/stream?token=<ticket>`。
3. 解析消息：
   - `init`：初始化监控状态。
   - `update`：增量更新。
   - `agent_event`：Agent 安装、更新、异常事件。
   - `remove`：移除主机状态。

移动端策略：

- 首页、监控页、主机详情页处于前台时保持连接。
- App 进入后台 5 秒后主动断开监控流。
- 回前台后先展示缓存，再重新连接。
- `host.lastSeenAt` 超过 15 秒显示离线或数据过期。
- 大列表只更新可见卡片，避免频繁重建全列表。

### 5.3 SSH 终端

连接流程：

1. `POST /api/auth/ws-ticket`。
2. `GET /api/ws/ssh/:hostId?ticket=<ticket>&record=true|false`。
3. 输入消息：

```json
{ "type": "input", "data": "ls -la\r" }
```

4. resize 消息：

```json
{ "type": "resize", "data": { "cols": 120, "rows": 32 } }
```

移动端终端设计：

- 使用 Flutter `xterm` 渲染。
- 横屏作为高密度终端主形态，竖屏保留可用但不追求桌面同等密度。
- 底部虚拟工具栏固定提供：Esc、Tab、Ctrl、Alt、方向键、Home、End、PgUp、PgDn、Ctrl-C、Ctrl-D、Ctrl-Z、粘贴、命令模板。
- 长按弹出菜单：复制、粘贴、全选、清屏、断开。
- 选择文本使用显式选择模式，避免系统文本选择和终端缓冲区冲突。
- App 后台默认断开 SSH，会话保留为“可重连”。不建议后台保持交互式 SSH。

### 5.4 SFTP 与长任务

基础接口：

- `GET /api/sftp/list/:hostId?path=...`
- `POST /api/sftp/upload/:hostId`
- `GET /api/sftp/upload-progress/:uploadId`
- `GET /api/sftp/download/:hostId?path=...`
- `POST /api/sftp/transfer`

移动端实现：

- 文件选择：`file_picker`。
- 下载保存：`path_provider` + 平台权限；无法直接保存时走 `share_plus`。
- 上传进度：生成 `uploadId`，提交 multipart 后轮询 `/upload-progress`。
- 跨主机传输：必须读取服务端 NDJSON 流，不能简化为普通 POST。
- 传输队列全局化：页面切换、锁屏、回前台后仍能看到任务状态。
- 大文件任务显示速度、ETA、失败原因、重试入口。

NDJSON 解析策略：

- 使用 Dio 或 `HttpClient` 发起请求。
- 按字节流累积 buffer。
- 按 `\n` 切行解析 JSON。
- `progress` 更新任务。
- `error` 标记失败。
- `complete` 标记完成并刷新目录。

### 5.5 录像播放

短期方案：

- 获取 ticket 后请求 `/api/recordings/:id/stream?token=...`。
- 解析 asciinema 内容，用 Flutter 终端回放组件播放。

中期建议：

- 后端提供录像元数据和分片读取接口，移动端按需加载，避免大文件一次性进入内存。

## 6. 信息架构

### 主导航

建议底部 4 个 Tab：

- 首页：在线状态、告警、最近连接、快速入口。
- 主机：主机列表、分组、搜索、连接、管理。
- 终端：会话列表、多会话切换。
- 文件：SFTP 最近主机、传输队列。

管理类入口放在个人/更多：

- 命令模板
- 连接历史
- 录像
- 用户管理
- 系统管理
- 网络模板
- 设置

### 首页卡片

- 在线主机数 / 离线主机数。
- CPU/内存/磁盘异常 Top N。
- 最近 SSH 会话。
- 正在进行的传输。
- Agent 部署/升级事件。

## 7. 开发里程碑

### P0：可安装可用

- Android APK 构建。
- 服务器地址配置。
- 登录、初始化、2FA、refresh token。
- 首页主机状态摘要。
- 主机列表和连接测试。
- 单 SSH 终端。
- SFTP 浏览、上传、下载、删除、重命名。

### P1：核心体验完整

- 多终端 session。
- 命令模板发送到终端。
- 监控详情页：CPU、内存、磁盘、网络、延迟。
- SFTP 传输队列和跨主机传输进度。
- Profile、改密、2FA 管理。
- 连接历史。

### P2：管理能力

- Agent 批量部署、停止、升级。
- 录像列表与播放。
- 用户管理。
- 系统信息、更新检查、数据库备份。
- 网络监控任务和模板。

### P3：移动端增强

- 生物识别解锁。
- Push / 本地通知。
- 离线缓存。
- iOS 完整适配。
- 平板布局。

## 8. 本地落地步骤

建议在现有 `mobile/flutter_app` 上重构，而不是新建第三个移动端目录。

### 8.1 依赖调整

```bash
cd /root/code/gitea/TermiScope/mobile/flutter_app
flutter pub add flutter_riverpod go_router dio flutter_secure_storage connectivity_plus file_picker path_provider share_plus permission_handler local_auth flutter_local_notifications intl
flutter pub get
```

### 8.2 开发运行

后端：

```bash
cd /root/code/gitea/TermiScope
go run ./cmd/server
```

Flutter：

```bash
cd /root/code/gitea/TermiScope/mobile/flutter_app
flutter run
```

Android APK：

```bash
cd /root/code/gitea/TermiScope/mobile/flutter_app
flutter build apk --release
```

### 8.3 第一批重构任务

1. 建立 `core/api/api_client.dart`，替换散落的 HTTP 调用。
2. 建立 `core/storage/secure_store.dart`，迁移 token 和 server URL。
3. 建立 `core/realtime/realtime_manager.dart`。
4. 重写 auth flow：登录、refresh、2FA、登出。
5. 重写 terminal feature：session controller + xterm view + 虚拟键盘。
6. 重写 monitor feature：WebSocket 状态流 + 首页摘要。
7. 重写 sftp feature：浏览器 + 传输队列。

## 9. 后端建议

不需要为移动端重写 API，但建议补齐：

- `allowed_origins` 支持移动端 WebSocket 来源，尤其是调试环境和反代域名。
- 增加 `/api/mobile/config` 返回版本、功能开关、上传限制、WebSocket idle timeout。
- SFTP 上传接口明确 `upload_id` 支持，便于移动端追踪。
- 长任务统一返回 `task_id`，并通过监控流或任务流推送状态。
- 增加设备会话字段，便于后台区分 Web、Android、iOS 登录。

## 10. 测试与验收

自动化：

- API client：登录、refresh、401、网络错误。
- RealtimeManager：断线、重连、前后台、网络切换。
- TerminalChannel：input、resize、binary output。
- SFTP transfer：NDJSON 分片解析。
- Store/controller：状态合并和错误恢复。

手工：

- Android 真机可登录并保持会话。
- WiFi/移动网络切换后监控流恢复。
- 终端横竖屏 resize 正确。
- 终端 Ctrl-C、方向键、粘贴可用。
- SFTP 上传/下载大文件进度准确。
- App 后台再回前台后状态可恢复。
- 普通用户和管理员入口权限正确。

## 11. 取舍说明

- 不复用 Web 后，Flutter 是更优选择：更强原生能力、更稳定终端交互、更好的移动端生命周期控制。
- Ionic/Angular 版本不建议继续作为正式主线：它已经偏离 Web 技术栈，又没有 Flutter 的原生优势。
- 直接 WebView 包装 Web 端不建议：终端、SFTP、键盘、下载和后台行为都会成为长期问题。
- 现有 `mobile/flutter_app` 可以继续利用，但应按上述架构重构，而不是在当前脚手架结构上继续堆页面。
