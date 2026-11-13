# TermiScope 在线与离线部署手册

本文依据当前源码、安装脚本和 Release 工作流编写，适用于 TermiScope 1.7.138 及同一发布结构的后续版本。正式发布资产位于 [GitHub Releases](https://github.com/ihxw/TermiScope/releases)，源码与提交历史以当前 Gitea 仓库为准。

## 1. 部署方式概览

| 场景 | 推荐方式 | 支持平台 | 是否需要目标机联网 |
| --- | --- | --- | --- |
| 容器部署 | Docker Compose + PostgreSQL，bridge 网络与持久化目录 | Linux amd64、arm64 | 拉取镜像或更新应用时需要 |
| 常规生产部署 | GitHub Release 在线安装脚本 | Linux、macOS、Windows | 是 |
| 隔离网、内网、受控变更 | 下载 Release 包和校验文件后离线安装 | Linux、macOS、Windows | 否 |
| 开发、验证或自定义构建 | 从源码构建或 Docker Compose | Linux 为主 | 构建阶段需要依赖源 |
| 已安装实例升级 | 管理界面可信升级、重新运行安装器或离线覆盖升级 | 取决于原部署方式 | 在线升级需要联网 |

Release 是生产部署的首选。Release 服务端使用 `CGO_ENABLED=0` 构建，包内已经包含 Web 静态资源和各平台监控 Agent，不要求目标机安装 Go、Node.js 或 npm。

当前 Release 由 Gitea Runner 构建后发布到 `ihxw/TermiScope` 的 GitHub Release，而不是发布到 Gitea Release。在线安装器、管理界面更新检查和 Agent 所需服务端文件都以该 GitHub Release 为准。

## 2. 支持的平台与发布资产

发布包命名规则如下：

```text
TermiScope-<版本>-<系统>-<架构>.<格式>
TermiScope-<版本>-<系统>-<架构>.<格式>.sha256
```

例如：

```text
TermiScope-1.7.138-linux-amd64.tar.gz
TermiScope-1.7.138-linux-amd64.tar.gz.sha256
```

| 系统 | 架构 | Release 文件 |
| --- | --- | --- |
| Linux | amd64 | `TermiScope-<版本>-linux-amd64.tar.gz` |
| Linux | arm64 | `TermiScope-<版本>-linux-arm64.tar.gz` |
| Linux | ARMv7 | `TermiScope-<版本>-linux-arm.tar.gz` |
| macOS | Intel amd64 | `TermiScope-<版本>-darwin-amd64.tar.gz` |
| macOS | Apple Silicon arm64 | `TermiScope-<版本>-darwin-arm64.tar.gz` |
| Windows | amd64 | `TermiScope-<版本>-windows-amd64.zip` |
| Windows | arm64 | `TermiScope-<版本>-windows-arm64.zip` |

按当前构建脚本生成的正式包包含以下内容：

```text
TermiScope 或 TermiScope.exe    服务端
web/dist/                       Web 控制台
agents/                         Linux、Windows、macOS 监控 Agent
configs/config.yaml.example     配置模板，不包含生产密钥
scripts/                        对应平台的安装及维护脚本
RELEASE_NOTES.md                发布说明（存在生成内容时）
DEPLOYMENT.md                   本部署手册
LICENSE
```

Linux 在线、离线安装脚本均按实际可用的服务管理器选择 systemd 或 OpenRC，不依赖 Debian 系列发行版。macOS 使用系统级 launchd，Windows 使用以 `SYSTEM` 身份运行的计划任务。

## 3. 部署前准备

### 3.1 资源与权限

- 使用具有 root、sudo 或 Windows 管理员权限的账户安装。
- 默认安装目录为 Linux/macOS 的 `/opt/termiscope`，Windows 的 `C:\Program Files\TermiScope`。
- OpenRC 安装目录请使用 `/opt/termiscope` 这类常规绝对路径，不支持空白或 shell 特殊字符。
- 新安装默认监听 TCP `3000`；配置模板和未指定配置时的代码默认值为 `8080`。以实际 `configs/config.yaml` 为准。
- 数据库为 SQLite，默认位于 `data/termiscope.db`。请为数据库、日志、录屏和传输临时数据预留空间。
- Linux/macOS 安装脚本需要 Bash；解包需要 `tar`、`gzip`，首次生成配置需要 `openssl`，在线下载需要 `curl` 和系统 CA 证书。Linux 在线安装器会按需通过 `apt-get`、`dnf`、`yum`、`microdnf`、`apk`、`pacman` 或 `zypper` 补齐依赖；离线安装不访问软件源，请提前准备依赖。
- Linux 需要运行中的 systemd，或具备 `rc-service`、`rc-update`、`openrc-run` 的 OpenRC 环境。缺少服务管理器时安装器会在停止旧服务或写入安装文件前报错；容器环境可使用 Docker Compose 部署。
- 离线目标机不需要 Go、Node.js 或 npm。

### 3.2 网络与防火墙

按实际功能放通以下方向：

| 方向 | 端口或目标 | 用途 |
| --- | --- | --- |
| 用户浏览器到 TermiScope | TCP 3000，或反向代理的 80/443 | Web、API、SSH WebSocket、监控 WebSocket |
| TermiScope 到被管理主机 | SSH 端口，通常为 TCP 22 | SSH、SFTP、Agent 部署和管理 |
| 被监控主机到 TermiScope | `server.public_base_url` 对应的 HTTP/HTTPS 端口 | Agent 心跳、指标、任务与中继传输 |
| TermiScope 到 GitHub | `api.github.com`、`github.com`、GitHub 资产域名的 HTTPS 443 | 在线安装和在线升级 |
| TermiScope 到其他服务 | 按需放通 SMTP、Telegram 等地址 | 可选通知功能 |

如果只允许从反向代理访问，应将应用端口限制在本机或可信网段，并只向用户开放 80/443。当前服务端监听 `:<port>`，即所有本机网络接口；访问范围需要由主机防火墙或反向代理控制。

### 3.3 备份要求

管理员可在 Web 控制台的“系统设置 > 数据”中选择“完整实例备份”。系统会在线生成
`.tar.gz` 迁移归档，包含当前服务工作目录中的程序、`web/dist`、Agent、配置、数据和日志；
运行中的 SQLite 数据库会被替换为一致性快照，因此不需要停服即可生成备份。归档实时流式发送
到浏览器，不会先在 `/tmp` 落地完整副本；数据库所在目录只会临时保存 SQLite 一致性快照。

归档的 `_migration/effective-config.yaml` 保存当前实际生效的配置，包括通过环境变量注入的
JWT 密钥和加密密钥；`_migration/README.txt` 提供迁移步骤。此归档包含主机凭据、密钥和日志，
必须通过可信渠道传输并妥善限制访问。

手工升级或迁移前至少备份：

```text
configs/config.yaml
data/
```

其中 `security.encryption_key` 用于解密已保存的主机凭据，不能丢失或随意更换；`security.jwt_secret` 用于签发会话。手工复制时，为获得一致的 SQLite 备份，应先停止服务，再复制整个 `data/`，包括可能存在的 `-wal` 和 `-shm` 文件。

使用完整实例备份迁移时，先停止目标端服务，将归档内 `termiscope/` 下的服务文件复制到目标
安装目录，检查 `database.path`、公开访问地址和文件属主后再启动。跨操作系统或 CPU 架构迁移时，
应先安装目标平台对应版本，再迁移 `configs/config.yaml`、`data/` 以及生效配置中的必要密钥。

## 4. 在线部署

### 4.1 Linux

精简系统需先准备执行入口使用的 Bash、curl 和 CA 证书。按目标系统选择命令，以 root 执行：

```bash
# RHEL、Rocky、AlmaLinux、Fedora（旧版 CentOS 可将 dnf 换为 yum）
dnf install -y bash curl ca-certificates
# Alpine
apk add --no-cache bash curl ca-certificates
# Arch Linux
pacman -S --needed --noconfirm bash curl ca-certificates
# openSUSE
zypper --non-interactive install bash curl ca-certificates
```

交互式安装最新 Release：

```bash
curl -fsSL https://github.com/ihxw/TermiScope/releases/latest/download/install.sh \
  -o /tmp/termiscope-install.sh
less /tmp/termiscope-install.sh
sudo bash /tmp/termiscope-install.sh
```

无人值守安装到默认目录和端口：

```bash
curl -fsSL https://github.com/ihxw/TermiScope/releases/latest/download/install.sh \
  | sudo bash -s -- -y
```

指定安装目录和新安装端口：

```bash
sudo bash /tmp/termiscope-install.sh \
  --install-dir /opt/termiscope \
  --port 3000 \
  -y
```

安装器会自动识别 `amd64`、`arm64` 或 ARMv7，下载匹配的最新包，生成强随机密钥，创建 `termiscope` 服务并启动。Debian、Ubuntu、RHEL、Rocky Linux 等 systemd 系统使用 `/etc/systemd/system/termiscope.service`；Alpine、Gentoo 等 OpenRC 环境使用 `/etc/init.d/termiscope`。依赖安装、发布包下载与必要文件检查均在停止旧服务前完成。

常用命令：

```bash
# systemd
sudo systemctl status termiscope
sudo systemctl restart termiscope
sudo journalctl -u termiscope -n 200 --no-pager

# Alpine OpenRC
sudo rc-service termiscope status
sudo rc-service termiscope restart
```

### 4.2 macOS

Intel 和 Apple Silicon 使用同一个安装命令，脚本会自动选择架构：

```bash
curl -fsSL https://github.com/ihxw/TermiScope/releases/latest/download/install.sh \
  -o /tmp/termiscope-install.sh
sudo bash /tmp/termiscope-install.sh
```

安装器默认安装到 `/opt/termiscope`，清除下载隔离属性，并注册 `/Library/LaunchDaemons/com.termiscope.server.plist`。

常用命令：

```bash
sudo launchctl print system/com.termiscope.server
sudo launchctl kickstart -k system/com.termiscope.server
sudo launchctl bootout system /Library/LaunchDaemons/com.termiscope.server.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.termiscope.server.plist
```

当前二进制未经过 Apple 公证。若手工下载后被 Gatekeeper 阻止，可执行：

```bash
sudo xattr -dr com.apple.quarantine /opt/termiscope
sudo launchctl kickstart -k system/com.termiscope.server
```

### 4.3 Windows

以管理员身份打开 Windows PowerShell 5.1 或更高版本：

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script = (New-Object Net.WebClient).DownloadString('https://github.com/ihxw/TermiScope/releases/latest/download/install.ps1')
& ([scriptblock]::Create($script))
```

无人值守安装：

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script = (New-Object Net.WebClient).DownloadString('https://github.com/ihxw/TermiScope/releases/latest/download/install.ps1')
& ([scriptblock]::Create($script)) -Y -Port 3000
```

也可以先下载并审查脚本：

```powershell
Invoke-WebRequest 'https://github.com/ihxw/TermiScope/releases/latest/download/install.ps1' -OutFile "$env:TEMP\install-termiscope.ps1"
& "$env:TEMP\install-termiscope.ps1" -InstallDir 'C:\Program Files\TermiScope' -Port 3000
```

安装器会创建名为 `TermiScope` 的开机计划任务。常用命令：

```powershell
Get-ScheduledTask -TaskName TermiScope
Start-ScheduledTask -TaskName TermiScope
Stop-ScheduledTask -TaskName TermiScope
```

Linux、macOS 和 Windows 在线安装脚本都通过 HTTPS 获取 GitHub 最新包，但当前安装脚本不读取旁路 `.sha256` 文件。对供应链校验有严格要求时，应使用下文的“下载、校验、转运、离线安装”流程。

## 5. 离线部署

离线部署分为两步：先在联网机器下载发布包及其 `.sha256`，校验通过后，再通过受控介质传入目标环境。

### 5.1 在联网机器准备文件

从 [GitHub Releases](https://github.com/ihxw/TermiScope/releases) 选择固定版本，不建议在变更窗口内使用会漂移的 `latest`。以下以 Linux amd64 的 `1.7.138` 为例：

```bash
VERSION=1.7.138
ASSET="TermiScope-${VERSION}-linux-amd64.tar.gz"
BASE_URL="https://github.com/ihxw/TermiScope/releases/download/v${VERSION}"

curl -fLO "${BASE_URL}/${ASSET}"
curl -fLO "${BASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
```

macOS 校验：

```bash
shasum -a 256 -c TermiScope-1.7.138-darwin-arm64.tar.gz.sha256
```

Windows 校验：

```powershell
$Package = 'TermiScope-1.7.138-windows-amd64.zip'
$Expected = ((Get-Content "$Package.sha256" -Raw) -split '\s+')[0].ToLowerInvariant()
$Actual = (Get-FileHash $Package -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA256 校验失败：$Package" }
"SHA256 校验通过：$Package"
```

将发布包和 `.sha256` 一起转运，并在离线目标机再次校验。不要使用 GitHub 自动生成的 `Source code` 压缩包代替 Release 资产；它不包含已构建服务端、Web 资源和 Agent。

### 5.2 Linux 离线安装（systemd / OpenRC）

```bash
tar -xzf TermiScope-1.7.138-linux-amd64.tar.gz
cd TermiScope-1.7.138-linux-amd64
sudo ./scripts/install_local.sh --install-dir /opt/termiscope --port 3000 -y
```

也可直接从压缩包安装：

```bash
sudo bash scripts/install_from_archive.sh \
  /path/to/TermiScope-1.7.138-linux-amd64.tar.gz \
  --install-dir /opt/termiscope \
  --port 3000 \
  -y
```

`install_local.sh` 自动选择 systemd 或 OpenRC。它不会覆盖已有的 `configs/config.yaml`、`data/` 和 `logs/`，因此也可用于同目录离线升级。缺少依赖时会提示并中止，不会联网安装软件。

### 5.3 Alpine Linux 离线安装

先在联网阶段准备好 Bash、tar、gzip 和 openssl，然后运行包内离线安装器，由其配置 OpenRC（root 账户可省略 `sudo`）：

```bash
tar -xzf TermiScope-1.7.138-linux-amd64.tar.gz
cd TermiScope-1.7.138-linux-amd64
sudo bash ./scripts/install_local.sh --install-dir /opt/termiscope --port 3000 -y
sudo rc-service termiscope status
```

### 5.4 macOS 离线安装

```bash
tar -xzf TermiScope-1.7.138-darwin-arm64.tar.gz
cd TermiScope-1.7.138-darwin-arm64
sudo ./scripts/install.sh --install-dir /opt/termiscope --port 3000 -y
sudo launchctl print system/com.termiscope.server
```

包内存在服务端和 `web/dist` 时，`install.sh` 自动进入离线模式，不会访问 GitHub。

### 5.5 Windows 离线安装

当前 Release 中的 `scripts/install.ps1` 是在线安装器，即使从解压目录运行也会访问 GitHub。完全离线的 Windows 环境应在管理员 PowerShell 中执行以下安装过程。该过程同时适用于升级，并保留已有配置和数据库。

先解压发布包：

```powershell
$Archive = 'D:\offline\TermiScope-1.7.138-windows-amd64.zip'
$ExtractDir = 'D:\offline\TermiScope-1.7.138'
Expand-Archive -Path $Archive -DestinationPath $ExtractDir -Force
$PackageBinary = Get-ChildItem $ExtractDir -Filter TermiScope.exe -File -Recurse | Select-Object -First 1
if (-not $PackageBinary) { throw '发布包中未找到 TermiScope.exe' }
$PackageRoot = $PackageBinary.Directory.FullName
```

停止旧实例并复制程序文件：

```powershell
$InstallDir = 'C:\Program Files\TermiScope'
$Task = Get-ScheduledTask -TaskName TermiScope -ErrorAction SilentlyContinue
if ($Task) {
    Stop-ScheduledTask -TaskName TermiScope -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName TermiScope -Confirm:$false
}
Get-CimInstance Win32_Process -Filter "Name = 'TermiScope.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq "$InstallDir\TermiScope.exe" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

@('configs', 'data', 'logs', 'agents', 'web', 'scripts') | ForEach-Object {
    New-Item -ItemType Directory -Path (Join-Path $InstallDir $_) -Force | Out-Null
}
Copy-Item "$PackageRoot\TermiScope.exe" "$InstallDir\TermiScope.exe" -Force
Remove-Item "$InstallDir\web\dist" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$PackageRoot\web\dist" "$InstallDir\web" -Recurse -Force
Copy-Item "$PackageRoot\agents\*" "$InstallDir\agents" -Recurse -Force
Copy-Item "$PackageRoot\scripts\*" "$InstallDir\scripts" -Recurse -Force
```

仅在首次安装且不存在配置时生成配置：

```powershell
$ConfigPath = "$InstallDir\configs\config.yaml"
if (-not (Test-Path $ConfigPath)) {
    function New-RandomHex([int]$ByteCount) {
        $Bytes = New-Object byte[] $ByteCount
        $Rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
        return (([BitConverter]::ToString($Bytes) -replace '-', '').ToLowerInvariant())
    }

    $JwtSecret = New-RandomHex 32
    $EncryptionKey = New-RandomHex 16
    $Port = 3000
    $Config = @"
server:
  port: $Port
  mode: release
  allowed_origins:
    - "http://localhost:$Port"
    - "http://127.0.0.1:$Port"
  max_upload_size: 1048576000

database:
  path: ./data/termiscope.db

security:
  jwt_secret: "$JwtSecret"
  encryption_key: "$EncryptionKey"

log:
  level: info
  file: ./logs/app.log
"@
    [IO.File]::WriteAllText($ConfigPath, $Config, (New-Object Text.UTF8Encoding($false)))
}
```

注册并启动计划任务：

```powershell
$Action = New-ScheduledTaskAction -Execute "$InstallDir\TermiScope.exe" -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal -UserId SYSTEM -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
Register-ScheduledTask -TaskName TermiScope -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description 'TermiScope Server' -Force | Out-Null
Start-ScheduledTask -TaskName TermiScope
```

## 6. 首次启动与验收

安装完成后访问：

```text
http://<服务器地址>:3000
```

系统没有预置管理员密码。首次打开页面时按照初始化界面创建管理员账户。

建议依次完成以下检查：

```bash
# 本机 API 和端口
curl -fsS http://127.0.0.1:3000/api/system/info

# Linux 服务和日志
sudo systemctl --no-pager --full status termiscope
sudo journalctl -u termiscope -n 100 --no-pager
sudo tail -n 100 /opt/termiscope/logs/server.log
sudo tail -n 100 /opt/termiscope/logs/error.log
```

- 浏览器可以进入初始化或登录页面。
- 添加一台测试主机后，SSH 和 SFTP 均可使用。
- 部署监控 Agent 后，被管理主机可以访问 `server.public_base_url`，监控页面能持续收到数据。
- 反向代理场景下，SSH WebSocket 与监控 WebSocket 不会被代理超时断开。
- 重启操作系统后，TermiScope 服务能自动启动。

## 7. 生产配置

### 7.1 配置文件与环境变量

运行配置位于安装目录的 `configs/config.yaml`。服务启动时会将其权限收紧为 `0600`。主要配置如下：

```yaml
server:
  port: 3000
  mode: release
  public_base_url: https://termiscope.example.com
  trusted_proxies:
    - 127.0.0.1
  allowed_origins:
    - https://separate-frontend.example.com
  max_upload_size: 1048576000
  timezone: Local

database:
  path: ./data/termiscope.db

security:
  jwt_secret: "至少 32 字节的随机值"
  encryption_key: "必须正好 32 字节"
  access_expiration: 60m
  refresh_expiration: 168h

ssh:
  timeout: 30s
  idle_timeout: 30m
  max_connections_per_user: 10
  sftp_concurrency: 32
  max_sftp_operations: 16
  max_sftp_operations_per_user: 8
```

明确支持的环境变量覆盖项：

| 环境变量 | 配置项 |
| --- | --- |
| `TERMISCOPE_PORT` | `server.port` |
| `TERMISCOPE_PUBLIC_BASE_URL` | `server.public_base_url` |
| `TERMISCOPE_DB_PATH` | `database.path` |
| `TERMISCOPE_JWT_SECRET` | `security.jwt_secret` |
| `TERMISCOPE_ENCRYPTION_KEY` | `security.encryption_key` |

非空环境变量优先于配置文件。生产环境必须固定 JWT 密钥和加密密钥；不要依赖容器或临时目录中的自动生成值。

`allowed_origins` 只用于跨源浏览器请求。使用同一域名反向代理 Web 与 API 时，不需要把该域名加入列表；前后端分离时才添加精确的 `scheme://host[:port]`。`release` 模式禁止使用 `*`。

### 7.2 HTTPS 反向代理

通过域名或 HTTPS 访问时，必须设置被监控主机也能访问的公开地址：

```yaml
server:
  public_base_url: https://termiscope.example.com
  trusted_proxies:
    - 127.0.0.1
```

`public_base_url` 决定 Agent 的回连地址。若 TLS 在 Nginx 终止而该配置留空，服务端可能生成错误的 `http://` 地址，表现为 Agent 安装成功但监控无数据。

也可在「系统管理 → 常规 → 公开访问地址」保存完整的 HTTPS 地址。非空的 `TERMISCOPE_PUBLIC_BASE_URL` 环境变量始终优先；未设置该变量时，界面保存的值即时生效，重启后从数据库恢复，优先于配置文件。从未在界面保存过该项时，沿用配置文件的值。修改配置文件需要重启 TermiScope；通过界面保存无需重启。两种方式都需要重新部署受影响主机的 Agent，才能更新目标主机上的上报地址。

容器部署无需创建 `config.yaml`：使用项目自带 Compose 时，在原部署目录的 `.env` 中设置 `TERMISCOPE_PUBLIC_BASE_URL=https://new.example.com`，然后运行 `docker compose up -d --no-deps --force-recreate termiscope`。仅执行 `docker restart` 不会应用新环境变量。配置了该环境变量后，界面会拒绝保存与它不同的公开地址，避免重启前后使用不同地址。

Nginx 参考配置：

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 443 ssl;
    server_name termiscope.example.com;

    ssl_certificate     /etc/letsencrypt/live/termiscope.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/termiscope.example.com/privkey.pem;

    client_max_body_size 1024m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 3600s;
        proxy_read_timeout 3600s;
    }
}
```

使用 `$http_host` 保留浏览器访问的域名和端口，以便终端和监控 WebSocket 正确校验同源请求，尤其是使用非默认 HTTPS 端口时。

只把实际代理 IP 或网段加入 `trusted_proxies`。不要为方便填写 `0.0.0.0/0`，否则客户端可伪造转发来源地址。HTTPS 证书必须受浏览器和所有被监控主机信任。

## 8. 升级、备份与回滚

### 8.1 管理界面在线升级

管理员可在系统设置中检查并执行升级。服务端只接受 GitHub 官方 Release 路径，并要求对应 `.sha256` 资产，下载后校验一致才替换程序。当前自动选择逻辑支持服务端 `amd64` 和 `arm64`；Linux ARMv7 请使用安装脚本或离线包升级。

从 1.7.136 起，使用官方镜像默认入口和持久化 `data/` 的容器同样支持 Web 更新。应用安装到 `data/application/` 的独立版本目录，完整切换服务端、Web、Agent 与安装模板；旧版容器需先按第9.1.8节更新一次镜像。

### 8.2 安装器升级

升级前停止服务并创建一致性备份：

```bash
sudo systemctl stop termiscope
sudo tar -C /opt -czf "termiscope-backup-$(date +%Y%m%d-%H%M%S).tar.gz" \
  termiscope/configs termiscope/data
sudo systemctl start termiscope
```

然后重新运行在线安装器，或用新版本离线包执行 `install_local.sh`。安装器会替换服务端、Web、Agent 和脚本，同时保留现有配置、数据和日志。`--port` 只对首次安装生效。

Windows 升级前应停止计划任务并复制 `configs`、`data`，然后重新运行在线安装器或执行 Windows 离线安装步骤。macOS 可重新运行包内 `install.sh`。

### 8.3 回滚

数据库迁移在启动时自动执行。不要只用旧二进制覆盖已经由新版本迁移过的数据库。可靠的回滚方式是：

1. 停止 TermiScope。
2. 保留失败版本现场。
3. 同时恢复升级前备份的程序、`web/dist`、`agents`、`configs/config.yaml` 和 `data/`。
4. 启动服务并检查 API、登录、SSH、SFTP 和监控数据。

## 9. Docker 与源码部署

### 9.1 Docker + PostgreSQL 部署

Docker 默认使用 **PostgreSQL 17 Alpine**，应用和数据库分别运行，数据库不开放宿主机端口。保留 SQLite 兼容用于旧实例与迁移，Docker 新部署不再使用 SQLite。PostgreSQL 支持并发事务和行级锁，可避免 SQLite 的全库单写者限制；它仍受 CPU、内存、磁盘和查询设计约束，不能承诺任意规模下没有性能瓶颈。

选择 PostgreSQL 是因为本项目同时保存账号、凭据、主机关系与高频监控数据，需要可靠事务、并发写入、成熟的 GORM 驱动及备份工具。MariaDB 也可满足关系数据需求，但同时支持多种服务型数据库会增加方言、迁移与维护成本。默认不增加 Redis、PgBouncer 或独立时序库。

#### 9.1.1 最低资源与容量边界

最低 **1 核 CPU、1 GB 内存**面向小规模实例，建议使用 SSD 与预构建镜像；源码编译应在资源充足的构建机器完成。应用容器上限 384 MB，Go 软内存目标 256 MiB、默认一个调度线程；PostgreSQL 容器上限 384 MB，给宿主系统保留约 256 MB。默认连接池 12/3，PostgreSQL 最大连接 24、shared_buffers 64 MB、work_mem 2 MB、maintenance_work_mem 32 MB。

这些参数是保守起点，不是主机数量承诺。`work_mem` 可能在一个查询中被多个执行节点使用；`effective_cache_size=256MB` 只是规划器估计，不额外分配对应内存。进程的有效数据超过内存上限仍可能被 OOM 终止。大量并行终端、文件传输、网络探测任务或长窗口历史查询应使用至少 2 核 2 GB，并按实测提高 `.env` 中的内存、连接池和 CPU 设置。

本次真实 PostgreSQL 兼容、并发正确性和部署验收见[验证记录](postgresql-validation.md)。验证使用 QEMU TCG 软件模拟，结果不能作为生产性能基准。

需要持续检查 `docker stats`、宿主磁盘空闲量、数据库/WAL 体积、健康状态、心跳成功率和慢查询。PostgreSQL 默认记录超过 1 秒的 SQL；监控数据保留期不是磁盘空间上限。`max_wal_size` 是检查点调节目标，也不是严格磁盘配额。

#### 9.1.2 使用 Release 部署包

正式 Release 提供 `TermiScope-Docker.tar.gz` 和 `.sha256`，包含固定应用版本的 Compose、配置模板、管理脚本与本手册。支持 Linux amd64 和 arm64；无需在服务器安装 Go、Node.js 或编译器。

在新的固定目录下载同一 Release 的两个文件；已有实例先按迁移步骤处理，勿用新空目录覆盖原部署：

```bash
mkdir -p /opt/termiscope-docker
cd /opt/termiscope-docker
curl -fLO https://github.com/ihxw/TermiScope/releases/latest/download/TermiScope-Docker.tar.gz
curl -fLO https://github.com/ihxw/TermiScope/releases/latest/download/TermiScope-Docker.tar.gz.sha256
sha256sum -c TermiScope-Docker.tar.gz.sha256
# macOS 可用 shasum -a 256 -c TermiScope-Docker.tar.gz.sha256
tar -xzf TermiScope-Docker.tar.gz
bash docker-deploy.sh up
```

首次启动仅在没有旧配置/数据库时生成 `.env` 中的三个独立随机密钥。脚本等待数据库及应用健康后才报告成功。访问 `http://服务器IP:3000` 创建管理员，没有预设账号。应用 `/api/health/ready` 检查实际数据库连通性，数据库异常不会被健康检查伪装为正常。

部署包尚未上传到目标 Release 时，上述下载地址不会存在；请使用实际已发布的 PostgreSQL 版本，或从本次源码构建。旧的只支持 SQLite 的镜像不能与此 Compose 搭配。

#### 9.1.3 从源码构建及环境配置

在完整源码根目录运行 `bash docker-deploy.sh up`。默认构建当前服务端、Web 和 Agent，再启动 PostgreSQL。使用预构建镜像时，在 `.env` 设置 `TERMISCOPE_IMAGE=命名空间/termiscope:版本号`、`TERMISCOPE_PULL_POLICY=always`，管理脚本会拉取镜像并跳过构建。

| 环境变量 | 用途与默认值 |
| --- | --- |
| `TERMISCOPE_PORT` | 宿主机映射端口，默认 3000；应用容器内部固定 3000 |
| `TERMISCOPE_BIND_ADDRESS` | 默认 0.0.0.0；宿主机反代可设 127.0.0.1 |
| `TERMISCOPE_PUBLIC_BASE_URL` | Agent 可访问的公开 HTTP/HTTPS 地址 |
| `TERMISCOPE_DB_NAME` / `TERMISCOPE_DB_USER` | PostgreSQL 数据库及账号，默认 termiscope |
| `TERMISCOPE_DB_PASSWORD` | PostgreSQL 独立密码；初始化后修改 .env 不会自动修改数据库账号密码 |
| `TERMISCOPE_JWT_SECRET` | 至少32字节，迁移时保留原值 |
| `TERMISCOPE_ENCRYPTION_KEY` | 恰好32字节，必须保留原值以解密已有凭据 |
| `TERMISCOPE_DB_MAX_OPEN_CONNS` / `TERMISCOPE_DB_MAX_IDLE_CONNS` | 应用连接池，默认12/3 |
| `TERMISCOPE_APP_MEMORY_LIMIT` / `TERMISCOPE_PG_MEMORY_LIMIT` | 容器内存上限，分别默认384m |
| `TERMISCOPE_GO_MEMORY_LIMIT` / `TERMISCOPE_GO_MAX_PROCS` | Go软内存目标256MiB、默认1；按主机资源调整 |
| `TERMISCOPE_PG_*` | PostgreSQL内存、连接数和慢查询设置，见 `.env.example` |

Compose 强制 `TERMISCOPE_DB_DRIVER=postgres`，通过内部网络连接 `postgres:5432`，连接失败不会回退到 SQLite。内部隔离网络使用 `sslmode=disable`；连接外部数据库时应按证书部署 `verify-full`，并调整 Compose 连接配置。

应用运行层复用 PostgreSQL Alpine 镜像，以提供同版本 `pg_dump`/`pg_restore`；入口为 `./main container-run`，由镜像程序管理持久化应用版本与重启，应用容器不会启动 PostgreSQL 服务。

#### 9.1.4 网络与宿主机功能

默认 bridge 网络支持 Linux Docker Engine 和 Docker Desktop，不需要 host 网络模式。PostgreSQL 仅加入内部网络，未配置 `ports`。应用仅发布配置的 HTTP 端口；通过 HTTPS 访问时设置公开地址，并沿用第7.2节的 WebSocket 代理配置。代理必须保留 `/api` 前缀。

应用没有 `privileged`、宿主 PID 或 `NET_ADMIN` 权限。Docker 内的本机防火墙及端口管理只能反映容器环境，**不能将其当作宿主机防火墙管理**。需要管理宿主机时，应通过该主机上的 Agent/SSH 或在宿主侧配置防火墙，不要为此默认赋予容器特权。连接宿主服务时，容器内的 `127.0.0.1` 指向应用容器；请使用可路由的宿主地址。

#### 9.1.5 数据持久化与日常管理

| 部署目录 | 用途 |
| --- | --- |
| Docker卷 `<COMPOSE_PROJECT_NAME>-postgres-data` | PostgreSQL 数据目录，默认卷名 `termiscope-postgres-data`，不依赖宿主目录属主 |
| `data/` | 录制、缓存、临时传输/备份文件及实例状态；`application/` 保存应用版本和更新状态 |
| `configs/` | 应用配置与持久化实例信息 |
| `logs/` | 应用日志 |
| `.env` | 数据库密码、JWT/AES密钥及部署参数，权限600 |
| `backups/` | 管理脚本生成的私有备份 |

保持原部署目录与 Compose 项目名。更换目录或数据库卷可能创建另一套数据库；不要手动删除 PostgreSQL 命名卷或初始化标记。部署脚本会拒绝在已有标记但命名卷缺失时启动；卷存在但内容异常时，应用的独立初始化标记仍会阻止开放 setup。不要复制正在运行的 PostgreSQL 数据目录作为备份。应用及数据库容器日志均按10 MB×3轮转。

```bash
bash docker-deploy.sh status
bash docker-deploy.sh logs --tail 100
bash docker-deploy.sh reset-pwd 管理员用户名
bash docker-deploy.sh restart  # 只重启应用
bash docker-deploy.sh stop     # 停止容器，保留所有数据
```

日常应用升级可在 Web 的更新入口执行，具体步骤与镜像更新边界见第9.1.8节。数据库主版本固定17，不能直接把已有数据卷改挂到更高主版本；主版本升级需按 PostgreSQL 的 dump/restore 或 pg_upgrade 流程执行。

#### 9.1.6 从脚本安装的 SQLite 实例迁移

迁移不会自动在已有 PostgreSQL 用户表上合并数据；目标必须为空。源库只读，保留主键、密码哈希及加密字段；**原 AES 密钥必须一起迁移**。加密字段不会因为更换数据库而重新加密。

1. 先备份旧 SQLite；用当前版本完成旧库结构升级并确认正常，再记录原服务目录、端口、密钥来源和版本，停止旧服务。迁移工具严格核对表和字段，未知表/字段或缺失字段会拒绝迁移，避免静默遗漏数据。默认 systemd 命令为 `sudo systemctl stop termiscope`。旧实例使用环境变量密钥时，以实际环境值为准。
2. 保存停服后原数据库及相关 WAL/SHM、配置、录制文件的一致性备份，保留旧安装目录作为回滚来源。
3. 在新的 Docker 部署目录解压部署包，执行 `cp .env.example .env`。填写**原 JWT/AES 密钥**及新的 PostgreSQL 密码；复制原配置到 `configs/`、录制等文件到 `data/`。不要直接 `up` 后创建新管理员。
4. 执行迁移并启动：

```bash
chmod 600 .env
bash docker-deploy.sh migrate-sqlite /opt/termiscope/data/termiscope.db --source-stopped
bash docker-deploy.sh up
```

脚本先启动数据库，使用只读挂载把旧库交给 `./main container-exec -migrate-sqlite`，目标非空或迁移失败则停止，不会标记成功。迁移成功后记录迁移标记，仍保留 SQLite 原文件。若旧库就在当前 `data/termiscope.db`，未完成迁移时 `up` 会拒绝直接忽略它。

5. 使用原账号登录，核对用户/主机数量、SSH凭据、监控历史及新心跳。保持原公开 URL 或更新 Agent 回连地址。确认后禁用旧服务的自动启动，避免端口竞争和两套实例同时接收请求。保留备份直至验收完成。

若来自旧 Docker 命名卷，先停止旧容器并用 `docker cp` 导出原 `data` 和 `configs`，同时保存原环境密钥。确认备用名称未被占用后执行 `docker rename termiscope termiscope-sqlite-old`，给新 Compose 留出容器名称；仅停止而不重命名仍会触发跨部署保护。保留改名后的旧容器及其卷作为回滚来源，再执行相同迁移。此阶段不要删除旧卷。

#### 9.1.7 PostgreSQL 备份、恢复与回滚

```bash
bash docker-deploy.sh backup
# 或指定一个尚不存在的备份目录
bash docker-deploy.sh backup /受控备份盘/termiscope-当天
```

备份包括一致的 `database.dump`、含密钥的 `deployment.env`、应用文件 `files.tar.gz`。`pg_dump` 可在服务在线时获得事务一致的数据库快照；录制和传输文件仍可能变化，需要严格文件快照时先 `docker compose stop termiscope`。备份应复制到另一台机器或独立存储并定期试恢复；仅保存在同一磁盘不能防止磁盘故障。

恢复前先保留目标现状并备份，确保使用可信的本项目归档。恢复命令会替换目标库中归档包含的对象，停止应用，并在单个事务内执行；失败回滚，应用保持停止。

```bash
bash docker-deploy.sh restore /备份目录/database.dump
# 核对并恢复同次备份的原密钥、配置和应用文件后再启动
bash docker-deploy.sh up
```

脚本不自动覆盖 `.env`、解压应用文件或启动恢复后的应用，避免错误密钥或不同版本与数据库组合。成功恢复后同样保持停服，供操作者核对。`pg_restore` 不是导入不可信 SQL 的沙箱，归档只能来自可信备份。

Web PostgreSQL 备份下载为 `.dump`；在线 Web 恢复不能安全替换正在服务的 PostgreSQL 实例，请使用上述停服流程。全量备份中的数据库格式和恢复说明以 manifest 为准。恢复 SQLite 文件不能直接覆盖 PostgreSQL 数据目录。 Web 完整备份会将容器的 `data`、`configs`、`logs` 链接展开为普通目录，并在归档顶层保存当前应用；为避免重复和递归，不包含 `data/application/` 版本仓库。恢复到容器时使用相同或兼容的应用镜像，再迁移配置和业务数据。部署脚本生成的 `files.tar.gz` 则保留整个应用版本仓库。

#### 9.1.8 容器内应用更新与镜像维护

**首次启用**：1.7.135 及更早的容器没有应用启动管理机制，仍需更新一次镜像。先执行 `bash docker-deploy.sh backup`，将同一部署目录的 Compose 和管理脚本更新为 1.7.136 或更高版本的 Release 文件，保留原 `.env`、数据卷及 `data/`、`configs/`、`logs/` 挂载。在 `.env` 中将 `TERMISCOPE_IMAGE` 设置为目标版本（例如 `iwlz/termiscope:v1.7.138`），然后执行 `bash docker-deploy.sh update`。使用 1Panel、Portainer 或自定义 Compose 时，采用新镜像的默认命令 `./main container-run`，不要覆盖为旧的 `./main`。

**日常应用更新**：管理员在 Web 中检查更新并执行升级。服务端从正式 Release 下载本架构安装包，验证 SHA256 后，将服务端、Web、Agent 与安装模板安装到 `data/application/` 下的独立目录，再由启动管理程序切换版本。此过程会短暂重启应用并断开终端连接；数据库容器保持运行。新版通过就绪检查后确认更新，启动失败则恢复上一版程序与资源。界面会核对实际上线的服务端版本，避免将回滚到旧版误报为成功。

`data/application/` 与其他数据一起持久化，不需要额外卷、Docker socket 或特权。重启或重建容器必须保留原 `data/` 挂载，不要单独删除该目录。Web 更新后的应用版本可以高于容器镜像标签；同一旧镜像重新创建容器时保留已更新应用，使用更高版本镜像时再切换到相应应用版本。系统信息显示的是当前运行的应用版本，镜像标签表示基础运行环境的版本。

**仍需更新镜像的范围**：操作系统、CA/时区数据、PostgreSQL 客户端及容器启动管理程序不在 Web 应用更新范围内。需要这些更新时，按首次启用的镜像更新步骤操作。Web 更新不能替代 PostgreSQL 主版本升级，也不会自动更新远端主机上已运行的 Agent；远端 Agent 沿用原有更新流程。

更新前执行备份并保留原密钥。自动回滚只恢复应用程序和静态资源，**不会撤销已经执行的数据库迁移**；若发行说明要求恢复数据库，应停止应用，并按对应版本的恢复步骤处理。不要仅降低 `TERMISCOPE_IMAGE` 标签来回退应用，因为持久化应用版本不会因此自动降级。

### 9.2 从源码构建

源码构建需要满足 `go.mod` 的 Go 版本（当前为 1.26.8）、满足 Vite 要求的 Node.js 20.19+/22.12+、npm、`tar`、`zip` 和 SHA256 工具。

构建全部正式资产：

```bash
bash build_release.sh
```

脚本会构建前端、七种服务端目标和各平台 Agent，并输出到 `release/`。如果只需要旧式 Linux amd64 离线包，可运行：

```bash
bash scripts/build_linux_amd64.sh
```

生产环境不要直接使用 `go run`，也不要只部署服务端二进制；服务端按相对路径读取 `configs/`、`data/`、`logs/`、`agents/` 和 `web/dist/`，systemd 或计划任务的工作目录必须是安装目录。

## 10. 卸载与故障排查

### 10.1 卸载

Linux/macOS 安装目录内的卸载脚本会删除程序、配置、数据库和日志，执行前必须备份：

```bash
sudo /opt/termiscope/uninstall.sh
```

Windows 卸载：

```powershell
Stop-ScheduledTask -TaskName TermiScope -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName TermiScope -Confirm:$false -ErrorAction SilentlyContinue
# 确认完成备份后，再手工删除 C:\Program Files\TermiScope
```

### 10.2 常见问题

| 现象 | 检查项 |
| --- | --- |
| 服务启动后页面 404 或空白 | 确认工作目录正确，且 `web/dist/index.html` 存在 |
| 启动时报密钥长度错误 | JWT 至少 32 字节；加密密钥必须正好 32 字节 |
| 反向代理后 Agent 无数据 | 设置 `public_base_url`，验证目标主机能解析并访问该 URL，然后重新部署 Agent |
| SSH 终端提示 WebSocket 连接失败 | 在浏览器 Network → WS 检查状态码：403 时检查代理是否保留原始 Host（含端口），跨站部署需在 `server.allowed_origins` 中明确配置浏览器来源；401 检查登录状态和票据，404 检查主机记录，500 检查凭据及加密密钥；代理还需转发 Upgrade/Connection 头 |
| SSH 终端能连接但经常断开 | 检查代理 WebSocket Upgrade/Connection 头和读写超时 |
| 上传大文件返回 413 | 同时增大 `server.max_upload_size` 和代理的 `client_max_body_size` |
| 获取的客户端 IP 不正确 | 只将实际反向代理加入 `trusted_proxies`，并检查 `X-Forwarded-For` |
| 在线安装找不到包 | 核对系统架构、GitHub 访问和最新 Release 是否包含对应资产 |
| 升级后凭据无法解密 | 恢复升级前的原始 `security.encryption_key` 和对应数据库 |
| SQLite 损坏或异常膨胀 | 停止服务后备份，使用包内 `repair_database.sh`；该脚本需要 sqlite3 3.37+ |

数据库修复示例：

```bash
sudo /opt/termiscope/repair_database.sh --data-dir /opt/termiscope/data
```

修复脚本会先备份数据库，优先尝试 `VACUUM INTO`，必要时执行 `.recover`。默认会清空可重建的 `network_monitor_results` 历史表；执行前应阅读脚本帮助和输出。

## 11. Release 发布流程（维护者）

Gitea 的 `.gitea/workflows/build_release_to_github.yaml` 负责正式发布：

1. 读取 `web/package.json` 的版本号，并与 GitHub 最新 Release 标签比较。
2. 仅当当前版本更高时生成基于 Gitea 提交历史的发布说明。
3. 运行 `build_release.sh` 构建七个平台包及其 `.sha256`。
4. 校验 Linux amd64、arm64 发布包的 SHA256，复用包内二进制、前端及 Agent 组装多架构镜像，推送到 Docker Hub 的 `v<版本>`、`<版本>` 标签；稳定版本同时更新 `latest`。镜像发布失败时停止后续 Release 发布。
5. 将最小安装落地页强制更新到 GitHub `main`，不公开 Gitea 源码。
6. 创建 `v<版本>` GitHub Release，并通过 GitHub API 上传所有包、校验文件、安装器和发布说明，附上对应镜像的启动命令。

Gitea 工作流支持手动运行：当前版本等于 GitHub 最新 Release 时，下载该 Release 已发布的 Linux 安装包和校验文件后补发镜像，不重新编译，以保证镜像与安装包的程序版本一致；版本更高时执行完整发布；版本更低时跳过。同版本补发不会重写既有 Release 正文或落地页，切换镜像仓库后的公开部署说明会在下一次新版本发布时更新。GitHub 落地页不包含源码或构建工作流，仓库中的旧 `.github/workflows/` 不参与当前正式发布。

发布前应至少完成：

```bash
bash scripts/ci/prepare_docker_test.sh
go test ./...
cd web
npm run build
cd ..
bash build_release.sh
```

更新版本时同时修改 `web/package.json` 和 `web/package-lock.json`，提交并推送 Gitea `main`。Runner 需要可用的 Go、Node.js/npm、`jq`、`zip`、`tar`、SHA256 工具以及配置正确的 `GH_TOKEN_SECRET`。Gitea 仓库不依赖本地 Git 标签触发发布；是否发布以 GitHub 最新 Release 与 Web 版本号的语义化比较结果为准。


### 11.1 镜像发布配置

工作流会在编译前检查 Docker Hub 凭据，执行 `scripts/ci/prepare_docker.sh` 准备 Docker CLI 并验证守护进程连接，再准备 Buildx 和登录 Docker Hub。缺少 CLI 时，脚本从 Docker 官方下载 Linux amd64/arm64 静态客户端（默认 29.6.1，可通过 Runner 环境变量 `DOCKER_CLI_VERSION` 覆盖），只提取客户端，并将路径写入 `GITHUB_PATH`，确保后续步骤及 post 清理阶段都能找到 `docker`。已有客户端时直接复用。

Gitea 的任务容器必须能访问 Docker 守护进程。Runner 能创建任务容器，并不代表该任务容器已经拥有 Docker CLI 和可用的 socket。使用宿主机 Docker 时，检查 act_runner 配置，例如：

```yaml
container:
  docker_host: "unix:///var/run/docker.sock"
```

Runner 自身也需要能访问该 socket。按 [Gitea Runner 配置说明](https://docs.gitea.com/runner/configuration/)，`container.docker_host` 留空会自动探测；设为 `-` 会禁止向任务容器挂载 socket，不适用于本工作流的本机 Docker 构建方式。使用远程 Docker 或独立 Docker-in-Docker 服务时，保留对应的 `DOCKER_HOST`、context 和 TLS 配置；准备脚本不会覆盖它们或启动新的守护进程。

若日志出现 `Unable to locate executable file: docker`，检查 Docker 准备步骤是否运行、下载是否成功；若提示 CLI 已就绪但无法访问守护进程，需修正 Runner 的 socket 或远程连接配置。预检失败会在编译前停止，避免到登录或清理阶段才发现问题。`Dockerfile.release` 复用已编译的 Release 内容及 PostgreSQL 官方镜像的客户端，目标架构阶段不执行命令，因此无需 QEMU。

先在 [Docker Hub](https://hub.docker.com/) 的个人或组织命名空间下创建 `termiscope` 仓库，选择 **Public**，使使用者可以免登录拉取。

在 Docker Home 点击头像 → Account settings → Personal access tokens → Generate new token，创建权限为 **Repo Read & Write** 的 PAT。该权限允许推送镜像，详见 [Docker 令牌说明](https://docs.docker.com/security/access-tokens/personal-access-tokens/) 和 [权限说明](https://docs.docker.com/security/access-tokens/reference/)。

在 **Gitea → TermiScope 仓库 → 设置 → Actions → Secrets** 中配置：

| Secret | 用途 |
| --- | --- |
| `DOCKERHUB_USERNAME` | 必填，Docker Hub 登录用户名，即令牌所属 Docker ID |
| `DOCKERHUB_TOKEN` | 必填，Docker Hub PAT，具备镜像读取和推送权限 |
| `DOCKERHUB_NAMESPACE` | 可选，目标 Docker Hub 组织名；不设置时使用 `DOCKERHUB_USERNAME` |
| `GH_TOKEN_SECRET` | 保留现有 GitHub Release 和落地页发布凭据 |

例如 `DOCKERHUB_USERNAME=alice` 时，默认发布 `alice/termiscope`；设置 `DOCKERHUB_NAMESPACE=myteam` 时，发布 `myteam/termiscope`，该用户必须拥有组织仓库的推送权限。

工作流分别登录 Docker Hub 和调用 GitHub 发布接口。镜像上传使用 Docker Hub PAT，GitHub Release 上传使用 `GH_TOKEN_SECRET`。工作流会将实际镜像名填入 GitHub README、部署手册和 Release 正文，用户可以直接复制一条命令运行。

若发布日志出现 `denied`，检查 Docker ID、PAT 权限与有效期、目标仓库所属命名空间和组织授权；匿名拉取失败时检查仓库是否为 Public。

#### Docker Hub 仓库部署说明

`docs/dockerhub_README.md` 是 Docker Hub 仓库 Overview 的部署说明模板，包含启动命令、Compose、持久化、代理、升级和备份。同步脚本会把 `iwlz/termiscope` 替换为实际镜像名，并同时更新仓库简短描述。

独立工作流 `.gitea/workflows/sync_dockerhub_description.yaml` 在说明模板、同步脚本、该工作流或 `web/package.json` 推送到 `main` 时运行，也可在 Gitea Actions 手动执行“同步 Docker Hub 部署说明”。仅更新说明无需增加版本号、重建镜像或连接 Docker 守护进程。

同步复用 `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN` 和可选的 `DOCKERHUB_NAMESPACE`，通过 [Docker Hub API](https://docs.docker.com/reference/api/hub/latest/) 认证并更新仓库。说明同步所用 PAT 应具备 **Repo Read, Write, Delete** 权限，其中包含仓库管理能力；组织仓库还需该用户具有仓库 Admin 权限，参见 [Docker 官方权限表](https://docs.docker.com/security/access-tokens/reference/) 和 [官方说明同步教程](https://docs.docker.com/build/ci/github-actions/update-dockerhub-desc/)。若出现 `403`，请检查上述权限，并在 Gitea Secrets 更新 `DOCKERHUB_TOKEN` 后手动重跑说明同步任务。说明同步的结果可在独立任务日志中查看。

### 11.2 Docker Hub 免费额度

Docker Personal 套餐目前为 **$0**，支持公开镜像仓库；公开仓库数量不限，但遵守公平使用规则。当前方案在 Gitea Runner 构建，再把成品镜像推送到 Docker Hub，可使用免费账户。Runner 与实际运行服务的服务器资源由部署者提供。

Docker Hub 对匿名和免费账户的拉取有速率限制，也有滥用请求限制。高频 CI 或大量用户共用一个出口 IP 时可能触发限流；账户实际额度以 [官方用量规则](https://docs.docker.com/docker-hub/usage/) 为准。套餐价格与功能见 [Docker 官方价格](https://www.docker.com/pricing/)。
