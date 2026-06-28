# TermiScope Web + 服务端安全审计报告

审计日期：2026-06-27  
审计范围：`cmd/server`、`internal/`、`web/src`、`web/package.json`、`Dockerfile`、`docker-compose.yml`、`configs/`。本报告聚焦 Web 前端与 Go 服务端；移动端未作为主要审计范围。

## 执行摘要

当前项目已经具备若干基础安全措施：大多数 API 走 JWT 鉴权，管理员接口有角色校验，数据库查询大多使用 GORM 参数绑定，SSH 主机凭据使用 AES-GCM 加密，密码使用 bcrypt，WebSocket 有 Origin 校验和一次性 ticket，CORS 默认不放开全部来源。

但本次审计确认存在多个需要优先处理的问题：

- 严重：仓库中跟踪了真实 `configs/config.yaml`，包含 `jwt_secret` 与 `encryption_key`，且 Docker 镜像会复制该文件。
- 高危：HTTP 日志会记录完整 query string，导致 WebSocket ticket、备份下载 token、agent monitor secret 等可能落入日志。
- 高危：未加密数据库备份会把服务端加密密钥附加进备份文件，备份泄露即等价于数据库和 SSH 凭据整体泄露。
- 高危：服务端在线更新只校验下载域名，不校验发布资产签名或固定来源，存在供应链执行风险。
- 高危：前端依赖审计发现 9 个 npm 漏洞，其中 5 个 high。
- 中危：前端把 access token 和 refresh token 放在 `localStorage`，XSS 后会直接泄露长期会话。
- 中危：密码重置链接信任请求 `Origin` / `X-Forwarded-*` 头构造域名，存在重置 token 泄露到攻击者域名的风险。

## 审计限制

- Go 依赖漏洞检查未完成：当前环境没有 `go` 命令，`govulncheck` 无法运行。
- 未进行动态渗透测试、模糊测试、真实部署反向代理验证。
- 未审计移动端 Flutter 代码、CI/CD 凭据、生产服务器文件权限和真实日志。

已执行检查：

- 静态代码审计：路由、鉴权、CORS、安全头、凭据存储、SFTP、SSH WebSocket、agent、备份恢复、更新流程。
- 前端依赖审计：`cd web && npm audit --audit-level=low`。
- Go 依赖审计尝试：`go run golang.org/x/vuln/cmd/govulncheck@latest ./...`，失败原因：`go: command not found`。

## 详细发现

### S-01 严重：真实密钥文件被提交并进入 Docker 镜像

证据：

- `configs/config.yaml` 被 git 跟踪：`git ls-files configs/config.yaml` 返回该文件。
- [configs/config.yaml](/root/code/gitea/TermiScope/configs/config.yaml:6) 包含真实 `encryption_key` 和 `jwt_secret`。
- [.gitignore](/root/code/gitea/TermiScope/.gitignore:47) 已声明忽略 `configs/config.yaml`，但文件已经被跟踪，忽略规则不再生效。
- [Dockerfile](/root/code/gitea/TermiScope/Dockerfile:33) 将 `/app/configs/config.yaml` 复制进最终镜像。
- [configs/config.example.yaml](/root/code/gitea/TermiScope/configs/config.example.yaml:1) 明确提示不要提交真实配置。

影响：

- 泄露 `jwt_secret` 后，攻击者可伪造任意用户/管理员 JWT。
- 泄露 `encryption_key` 后，数据库中的 SSH 密码、私钥、2FA secret、通知凭据等可被离线解密。
- Docker 镜像和发布包如果包含该配置，会导致所有部署实例共享同一组密钥。

修复建议：

- 立即轮换生产 `JWT_SECRET` 和 `ENCRYPTION_KEY`，同时失效所有会话。
- 从 git 中移除该文件：`git rm --cached configs/config.yaml`，保留本地文件。
- 使用环境变量或部署 secret 注入：`TERMISCOPE_JWT_SECRET`、`TERMISCOPE_ENCRYPTION_KEY`。
- Dockerfile 不应复制真实 `config.yaml`；应复制 `config.example.yaml` 或运行时生成配置目录。
- 如果该仓库曾经推送到远端，使用 `git filter-repo` 或同等工具清理历史，并视为密钥已经泄露。

优先级：P0。

### S-02 高危：请求日志记录完整 query，泄露 token / secret

证据：

- [internal/middleware/logger.go](/root/code/gitea/TermiScope/internal/middleware/logger.go:29) 注释说要清理 `token`，但实际 [logger.go](/root/code/gitea/TermiScope/internal/middleware/logger.go:38) 直接拼接 `RawQuery`。
- [cmd/server/main.go](/root/code/gitea/TermiScope/cmd/server/main.go:127) 使用 `gin.Default()`，它自带 Gin Logger；随后 [cmd/server/main.go](/root/code/gitea/TermiScope/cmd/server/main.go:134) 又注册自定义 Logger。
- 多个接口把敏感值放在 query：
  - WebSocket monitor stream：`/api/monitor/stream?token=...`，见 [monitor_stream_auth.go](/root/code/gitea/TermiScope/internal/handlers/monitor_stream_auth.go:12)。
  - SSH WebSocket：`/api/ws/ssh/:hostId?ticket=...`，见 [ssh_ws.go](/root/code/gitea/TermiScope/internal/handlers/ssh_ws.go:83)。
  - 备份下载：`/api/system/backup/download?token=...`，见 [admin_ticket_auth.go](/root/code/gitea/TermiScope/internal/middleware/admin_ticket_auth.go:47)。
  - agent install/uninstall：`secret` query，见 [host_access.go](/root/code/gitea/TermiScope/internal/handlers/host_access.go:84)。

影响：

- 日志文件、反向代理 access log、错误排查截图都可能包含一次性 ticket 或长期 monitor secret。
- 一次性 ticket 虽然 30 秒有效且一次性，但日志泄露在高并发/集中日志系统中仍有窗口风险。
- monitor secret 是长期密钥，泄露后攻击者可伪造 agent 上报、获取 agent manifest/二进制、触发卸载回调等。

修复建议：

- 不使用 `gin.Default()`，改成 `gin.New()`，只注册已审计的 Logger/Recovery。
- Logger 必须解析 query 并脱敏：`token`、`ticket`、`secret`、`refresh_token`、`password`、`Authorization` 等。
- 对 agent install/uninstall 下载优先强制使用 `Authorization: Bearer`，废弃 `?secret=`。
- 现有日志按泄露处理：清理、限制访问、轮换 monitor secrets。

优先级：P0。

### S-03 高危：未加密备份包含服务器加密密钥

证据：

- [internal/handlers/system.go](/root/code/gitea/TermiScope/internal/handlers/system.go:171) 在无备份密码时调用 `AppendKeyTrailer`，把 `encryption_key` 追加到 `.db` 备份。
- [system.go](/root/code/gitea/TermiScope/internal/handlers/system.go:194) 备份下载允许管理员通过 JWT/cookie/ticket 下载。

影响：

- 未加密备份文件一旦泄露，攻击者不仅拿到数据库，还拿到解密数据库内敏感字段的密钥。
- 这会导致 SSH 密码/私钥、TOTP secret、SMTP/Telegram 凭据整体泄露。

修复建议：

- 默认禁止未加密备份，强制要求备份密码。
- 不要把 `encryption_key` 放入普通 `.db` 文件；如需迁移，应使用单独的加密导出格式，并要求管理员显式确认。
- 对已有未加密备份按密钥泄露处理，轮换 `encryption_key` 并重新加密存量敏感数据。

优先级：P0/P1。

### S-04 高危：服务端在线更新缺少签名/校验链

证据：

- [internal/handlers/system.go](/root/code/gitea/TermiScope/internal/handlers/system.go:588) 只校验下载 URL 的域名为 GitHub 相关域名。
- [internal/updater/updater.go](/root/code/gitea/TermiScope/internal/updater/updater.go:127) 直接下载、解包、替换当前二进制并重启。
- [updater.go](/root/code/gitea/TermiScope/internal/updater/updater.go:418) 只查找包内 `TermiScope` 二进制，没有签名验证。

影响：

- 如果 GitHub release、下载链接、管理员浏览器或上游供应链被攻击，服务端会执行攻击者二进制。
- 由于服务端可能以 root 或具备防火墙权限运行，后果是主机级 RCE。

修复建议：

- 更新包必须带签名，服务端内置公钥验证，例如 cosign/minisign/age-signify。
- 更新接口不要接受任意 `download_url`；应只使用 `CheckUpdate` 返回的固定 repo asset，并验证 release tag、asset 名称、sha256 和签名。
- 更新过程写入审计日志，展示签名主体、hash、版本。

优先级：P1。

### S-05 高危：npm 依赖存在已知漏洞

命令：`cd web && npm audit --audit-level=low`

结果：9 个漏洞，包含 5 个 high、3 个 moderate、1 个 low。主要项：

- `axios`：high，多项 SSRF / prototype pollution / header injection / DoS 类 advisory。
- `form-data`：high，multipart 字段/文件名 CRLF injection。
- `lodash`、`lodash-es`：high，code injection / prototype pollution。
- `vite`：high，多项 dev server 任意文件读取/路径穿越。
- `dompurify` 经 `monaco-editor` 引入：moderate，多项 XSS bypass。
- `follow-redirects`：moderate，跨域重定向泄露自定义认证头。
- `postcss`：moderate，CSS stringify XSS。

修复建议：

- 运行 `cd web && npm audit fix` 并验证构建。
- 对 `monaco-editor` 相关的 breaking change 单独评估；必要时固定到安全版本或等待上游补丁。
- 补充依赖审计到 CI，至少对 high/critical 阻断合并。

优先级：P1。

### S-06 中危：前端会话 token 存储在 localStorage

证据：

- [web/src/stores/auth.js](/root/code/gitea/TermiScope/web/src/stores/auth.js:7) 从 `localStorage` 读取 access token 和 refresh token。
- [auth.js](/root/code/gitea/TermiScope/web/src/stores/auth.js:24) 登录后写入 `localStorage`。
- [web/src/api/index.js](/root/code/gitea/TermiScope/web/src/api/index.js:14) 每次请求从 `localStorage` 取 token 放入 `Authorization`。
- 服务端同时设置 HttpOnly `access_token` cookie，见 [internal/handlers/auth.go](/root/code/gitea/TermiScope/internal/handlers/auth.go:22)。

影响：

- 一旦出现 XSS，攻击者可直接读取 refresh token 并长期维持会话。
- 当前 CSP 允许 `unsafe-inline`，见 [security.go](/root/code/gitea/TermiScope/internal/middleware/security.go:13)，对 XSS 缓解有限。

修复建议：

- refresh token 改为 HttpOnly + Secure + SameSite cookie；access token 放内存或短期 cookie。
- 移除 `localStorage` 中的 refresh token。
- 所有使用 cookie 的状态变更请求增加 CSRF token 或双提交策略。
- 逐步收紧 CSP，生产构建移除 `script-src 'unsafe-inline'`。

优先级：P1/P2。

### S-07 中危：密码重置链接可被 Host/Origin 头污染

证据：

- [internal/handlers/auth.go](/root/code/gitea/TermiScope/internal/handlers/auth.go:1015) 优先使用请求 `Origin`。
- 如果没有 `Origin`，则 [auth.go](/root/code/gitea/TermiScope/internal/handlers/auth.go:1017) 使用 `X-Forwarded-Host`，并在 [auth.go](/root/code/gitea/TermiScope/internal/handlers/auth.go:1021) 使用 `X-Forwarded-Proto`。
- [auth.go](/root/code/gitea/TermiScope/internal/handlers/auth.go:1028) 直接拼接 reset link。

影响：

- 攻击者可对受害者邮箱触发重置邮件，并让邮件里的链接指向攻击者域名。
- 如果用户点击链接，reset token 会出现在攻击者站点的 URL 中。

修复建议：

- 增加配置项 `public_base_url`，重置邮件只使用该固定值。
- 如果必须使用请求头，必须通过 `IsOriginAllowed` 和可信代理配置校验。
- 不信任来自客户端的 `X-Forwarded-*`，只在可信反向代理层覆盖并清理。

优先级：P1/P2。

### S-08 中危：agent monitor secret 暴露面过大

证据：

- agent install/uninstall 支持 `?secret=`，见 [host_access.go](/root/code/gitea/TermiScope/internal/handlers/host_access.go:84)。
- 安装脚本把 secret 写入脚本文本，见 [monitor.go](/root/code/gitea/TermiScope/internal/handlers/monitor.go:2087)。
- systemd `ExecStart` 中包含 `-secret "..."`，见 [monitor.go](/root/code/gitea/TermiScope/internal/handlers/monitor.go:1012)。
- agent 进程参数使用 `-secret`，本机其他有权限用户可能通过进程列表读取。

影响：

- monitor secret 是长期凭据，泄露后可伪造 agent 请求。
- secret 出现在 URL、脚本、systemd unit、进程参数、日志、shell history 的概率较高。

修复建议：

- secret 不走 URL；只走 `Authorization` header 或短期安装 token。
- agent secret 存到 root-only 配置文件或 systemd `EnvironmentFile`，权限 `0600`，避免命令行参数。
- 增加 monitor secret 轮换接口，泄露后可按主机快速轮换。
- logger 强制脱敏 query 和 header。

优先级：P1/P2。

### S-09 中危：2FA 设置流程把 TOTP secret 交给客户端再回传

证据：

- [internal/handlers/twofa.go](/root/code/gitea/TermiScope/internal/handlers/twofa.go:85) `Setup2FA` 返回明文 secret、QR code 和 URL。
- [twofa.go](/root/code/gitea/TermiScope/internal/handlers/twofa.go:108) `VerifySetup2FA` 要求客户端通过 `X-2FA-Secret` 回传 secret。

影响：

- TOTP secret 可能进入浏览器内存、调试工具、代理日志、前端错误日志。
- 如果已有会话被盗，攻击者可给账号绑定自己的 2FA；当前设置 2FA 不要求重新输入密码。

修复建议：

- 服务端保存 pending 2FA secret，短期有效，验证成功后启用；客户端只显示 QR，不负责回传 secret。
- 设置、禁用、重新生成 backup codes 前要求重新认证密码或通过现有 2FA。
- 对 2FA 验证失败按用户和 temp token 做额外速率限制。

优先级：P2。

### S-10 中危：备份/恢复和 SFTP 上传缺少明确总请求大小上限

证据：

- [cmd/server/main.go](/root/code/gitea/TermiScope/cmd/server/main.go:132) 设置 `router.MaxMultipartMemory`，但这不是总请求体大小限制。
- [internal/handlers/system.go](/root/code/gitea/TermiScope/internal/handlers/system.go:231) restore 接收上传文件并保存到临时目录。
- [internal/handlers/sftp.go](/root/code/gitea/TermiScope/internal/handlers/sftp.go:434) SFTP upload 使用 streaming multipart reader，没有看到 `http.MaxBytesReader`。

影响：

- 恶意或误操作的大文件可造成磁盘、网络、远端 SFTP 写入资源耗尽。

修复建议：

- 在 upload/restore handler 入口使用 `http.MaxBytesReader`。
- 对 restore 设置独立上限，例如 1-2GB 或按配置。
- 对 SFTP upload 使用配置的 `max_upload_size` 做硬限制，并在前后端都校验。

优先级：P2。

### S-11 中危：管理员可明文查看通知凭据，用户可 reveal SSH 凭据

证据：

- [internal/handlers/system.go](/root/code/gitea/TermiScope/internal/handlers/system.go:400) `GetSettings` 解密并返回 `smtp_password`、`telegram_bot_token`。
- [internal/handlers/ssh_host.go](/root/code/gitea/TermiScope/internal/handlers/ssh_host.go:215) `?reveal=true` 可返回 SSH 密码/私钥。

影响：

- 已登录会话被盗后，攻击者可直接导出凭据，而不只是使用系统代操作。
- 管理员界面、浏览器扩展、前端错误日志都可能接触明文 secret。

修复建议：

- 默认不回传完整敏感值，只返回“已设置”状态。
- reveal 操作要求重新输入密码/2FA，且写安全审计日志。
- 系统通知密钥更新采用 write-only 字段，不在 GET settings 返回明文。

优先级：P2。

### S-12 低到中危：生产配置中允许多个 localhost CORS origin

证据：

- [configs/config.yaml](/root/code/gitea/TermiScope/configs/config.yaml:13) release 配置允许多个 localhost origin。
- [internal/middleware/cors.go](/root/code/gitea/TermiScope/internal/middleware/cors.go:30) 对允许 origin 设置 `Access-Control-Allow-Credentials: true`。

影响：

- 如果生产用户访问系统时浏览器里已有认证 cookie，运行在本机 `localhost:5173/3000/8080` 的恶意页面可向服务端发起 credentialed CORS 请求并读取响应。
- 对仅使用 Bearer header 的攻击门槛更高，但 cookie fallback 存在。

修复建议：

- 生产 `allowed_origins` 只保留真实业务域名。
- 开发 origin 只在 debug mode 或本地配置中启用。
- 增加启动时 release + localhost origin 的 warning 或拒绝。

优先级：P2。

## 已有防护点

- JWT 校验要求 access token 类型，非 access token 不能访问普通受保护 API，见 [auth.go](/root/code/gitea/TermiScope/internal/middleware/auth.go:84)。
- 已移除普通 API 的 URL token 支持，见 [auth.go](/root/code/gitea/TermiScope/internal/middleware/auth.go:28)。
- WebSocket ticket 是短期一次性，见 [ticket.go](/root/code/gitea/TermiScope/internal/utils/ticket.go:57) 和 [ticket.go](/root/code/gitea/TermiScope/internal/utils/ticket.go:74)。
- SSH 主机凭据使用 AES-GCM 加密，见 [crypto.go](/root/code/gitea/TermiScope/internal/utils/crypto.go:16)。
- 用户密码使用 bcrypt，见 [user.go](/root/code/gitea/TermiScope/internal/models/user.go:59)。
- CORS 有白名单和 Origin 校验，见 [origin.go](/root/code/gitea/TermiScope/internal/middleware/origin.go:10)。
- SQL 查询大多使用参数绑定，未发现明显字符串拼接 SQL 注入。
- SSH host key 使用 TOFU + 后续指纹校验，见 [client.go](/root/code/gitea/TermiScope/internal/ssh/client.go:71)。

## 修复优先级建议

P0，立即处理：

1. 轮换 `jwt_secret`、`encryption_key`，移除被跟踪的 `configs/config.yaml`，修正 Dockerfile。
2. 停止记录敏感 query，替换 `gin.Default()`，日志脱敏；轮换已可能进入日志的 monitor secrets。
3. 重新评估现有备份文件，移除未加密备份中的密钥 trailer 或强制加密备份。

P1，短期处理：

1. 修复 npm high 漏洞并加入 CI 审计。
2. 为服务端更新包加入签名验证，限制下载源。
3. 固定密码重置 `public_base_url`。
4. 调整 agent secret 存储方式，避免 URL 和进程参数。

P2，中期处理：

1. 会话改造：refresh token 迁移到 HttpOnly Secure cookie，减少 localStorage 使用。
2. 2FA pending secret 服务端保存，敏感操作要求重新认证。
3. 设置 upload/restore 总请求体大小上限。
4. 敏感配置改为 write-only，凭据 reveal 增加再认证和审计。
5. 生产 CORS 配置只允许正式域名。

## 验证清单

修复后建议补充以下自动化检查：

- 单元测试：logger 对 `token`、`ticket`、`secret`、`password` query 做脱敏。
- 集成测试：`/api/system/backup/download` 的 ticket 仍可一次性使用，但日志不含 token。
- 集成测试：生产模式下禁止 `allowed_origins: ["*"]` 和 localhost origin。
- 单元测试：密码重置链接只使用 `public_base_url`。
- E2E：登录、刷新、WebSocket ticket、SFTP 上传、备份下载在新会话方案下正常。
- CI：`npm audit --audit-level=high`、`govulncheck ./...`。
