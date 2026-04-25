<div align="center">
  <img src="./web/public/logo.png" width="100" />
  <h1>TermiScope</h1>
  <p>
    <strong>现代化、轻量级的服务器管理与监控平台</strong>
  </p>
  <p>
    <a href="https://go.dev/"><img src="https://img.shields.io/badge/Backend-Go_1.25+-blue.svg" alt="Go"></a>
    <a href="https://vuejs.org/"><img src="https://img.shields.io/badge/Frontend-Vue3-green.svg" alt="Vue 3"></a>
    <a href="https://hub.docker.com/"><img src="https://img.shields.io/badge/Docker-Ready-blue.svg" alt="Docker"></a>
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License">
  </p>
</div>

TermiScope 是一个功能强大且支持自托管的服务器管理工具，旨在简化 DevOps 工作流。它结合了全功能的 Web SSH 终端、全面的服务器状态监控、网络连通性检测和安全审计流程，支持多语言、多主题以及高度自定义的配置。

---

## ✨ 功能特性

### 🖥️ Web 终端与 SFTP
- **全功能 SSH 客户端**：基于 `xterm.js`，支持所有标准 SSH 交互，提供与本地终端一致的体验。
- **多标签页管理**：支持同时连接多个主机，通过标签页快速切换。
- **自定义主题**：支持 9 款精选主题（Termius Dark/Light、Dracula、Monokai、Solarized、GitHub、VS Code），采用反色高亮选中文字，提升可读性。
- **文件管理 (SFTP)**：支持 Zmodem 协议和内置可视化的 SFTP 浏览器，支持拖拽上传/下载。
- **凭据管理与自动填充**：安全存储 SSH 密码和密钥，支持编辑主机时自动填充已存密码。
- **虚拟键盘**：为移动端浏览器提供快捷按键支持（Ctrl/Alt/Shift、方向键、特殊字符等）。
- **会话录像**：支持录制 SSH 终端会话，供后续审计回放。

### 📊 服务器与网络监控
- **轻量级跨平台 Agent**：支持 Linux、Windows、macOS 和 FreeBSD，一键下发和管理。
- **实时系统性能监控**：直观展示 CPU、内存、磁盘和网络 I/O 实时状态。
- **网络延迟监控**：支持 ICMP Ping 和 TCP Ping 协议的节点连通性检测，交互式图表展示历史数据和丢包率。
- **流量限制预警**：支持为主机配置月度流量配额以及账单结算日，超限直观展示。

### 🛡️ 安全与审计
- **动态审批工作流**：支持可配置的安全审计与审批工作流管理，细致追踪每一个操作环节。
- **多语言与本地化 (i18n)**：全界面支持国际化（中英切换等）。
- **全局时区设置**：支持自定义全局时区，统一日志与会话记录的时间戳展示。
- **身份验证与鉴权**：
  - 双重身份验证 (2FA / TOTP，例如 Google Authenticator, Authy)。
  - 基于角色 (Admin/User) 的访问权限控制。
  - 核心敏感配置与凭据使用 AES-256 高强度加密。
  - API 与 Agent 通信频率限制 (Rate Limiting) 抵御暴力破解。

---

## ⚙️ 系统配置项 (config.yaml)

启动系统前，可以通过修改 `configs/config.yaml` 灵活调整后端服务和安全策略：

### Server（服务器配置）
| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `server.port` | `3000` | 后端服务监听绑定的端口号 |
| `server.mode` | `debug` | 运行模式：`debug` (输出更多日志) 或 `release` (生产环境精简日志) |
| `server.allowed_origins` | `["http://localhost:5173", ...]` | 允许的跨域请求源（CORS）。生产环境建议只保留实际域名，若前后端同源可清空 |
| `server.max_upload_size` | `1048576000` | 允许的最大文件上传尺寸（默认约 1000MB） |

### Database（数据库配置）
| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `database.path` | `./data/termiscope.db` | 本地 SQLite 数据库文件存放路径 |

### Security（安全配置）
| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `security.jwt_secret` | `""` | JWT Token 签名密钥。留空则首次启动自动生成。建议通过 `TERMISCOPE_JWT_SECRET` 环境变量注入 |
| `security.encryption_key` | `""` | 数据加密密钥（AES-256，需要正好 32 字节大小）。建议通过 `TERMISCOPE_ENCRYPTION_KEY` 环境变量注入 |
| `security.smtp_tls_skip_verify` | `false` | 是否跳过 SMTP TLS 验证。生产环境务必为 `false` |

### Log（日志配置）
| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `log.level` | `info` | 记录日志的等级，如 `debug`, `info`, `warn`, `error` |
| `log.file` | `./logs/app.log` | 输出的日志文件路径 |

---

## 🚀 快速开始

### 方式一：一键安装脚本 (推荐 Linux/macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/ihxw/TermiScope/main/scripts/install.sh | bash
```

### 方式二：手动运行二进制包
1. 从 [Releases 页面](https://github.com/ihxw/TermiScope/releases) 下载适合您操作系统的压缩包。
2. 解压后运行服务端核心程序：
   ```bash
   # Linux / macOS
   chmod +x TermiScope
   ./TermiScope

   # Windows
   .\TermiScope.exe
   ```
3. 在浏览器中访问 `http://localhost:3000` 即可加载控制台。

### 方式三：Docker 部署
```bash
docker compose up -d
```

---

## 🛠️ 开发与构建指南

### 依赖环境
- **Go 1.25+** (后端)
- **Node.js 20+** (前端)

### 本地调试
```bash
git clone https://github.com/ihxw/TermiScope.git
cd TermiScope

# PowerShell 环境
./devRun.ps1

# 或分别启动
cd web && npm install && npm run dev    # 前端 -> http://localhost:5173
cd .. && go run cmd/server/main.go      # 后端 -> http://localhost:3000
```

### 构建发布
一键构建多平台架构的可执行文件：
```bash
./build_release.sh     # Bash 环境
# 或
./build_release.ps1    # PowerShell 环境
```
构建产物输出至 `release/` 目录。

---

## 📦 监控节点 (Agent) 部署

若希望在管理面板看到完整的服务器性能曲线，需要在目标机器上安装 Agent：

**控制面板推送部署 (推荐)**：
1. 登录前端，进入 **主机管理**。
2. 选择待监控主机，点击 **部署监控** 按钮，系统自动下发 Agent 并设为守护进程。

**手工部署**：
```bash
chmod +x termiscope-agent
./termiscope-agent -server http://YOUR_TERMISCOPE_IP:3000 -secret YOUR_APP_SECRET -id HOST_ID
```

---

## 📚 API 文档

TermiScope 内置 Swagger API 在线文档。在 debug 模式下可访问：
`http://localhost:3000/swagger/index.html`

修改 API 接口后重新生成文档：
```bash
swag init -g cmd/server/main.go --parseDependency
```

## 📝 许可协议与版权声明
本项目基于 [MIT License](LICENSE) 授权开源发布。详细声明请参见根目录下的 LICENSE 文件。
