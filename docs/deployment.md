# TermiScope 在线与离线部署手册

本文依据当前源码、安装脚本和 Release 工作流编写，适用于 TermiScope 1.7.74 及同一发布结构的后续版本。正式发布资产位于 [GitHub Releases](https://github.com/ihxw/TermiScope/releases)，源码与提交历史以当前 Gitea 仓库为准。

## 1. 部署方式概览

| 场景 | 推荐方式 | 支持平台 | 是否需要目标机联网 |
| --- | --- | --- | --- |
| 容器部署 | Docker Hub 预构建镜像，默认 host 网络与运行目录持久化 | Linux amd64、arm64 | 拉取镜像时需要 |
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
TermiScope-1.7.74-linux-amd64.tar.gz
TermiScope-1.7.74-linux-amd64.tar.gz.sha256
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

Linux 安装脚本支持 systemd；通用 `install.sh` 还会在 Alpine Linux 上配置 OpenRC。macOS 使用系统级 launchd，Windows 使用以 `SYSTEM` 身份运行的计划任务。

## 3. 部署前准备

### 3.1 资源与权限

- 使用具有 root、sudo 或 Windows 管理员权限的账户安装。
- 默认安装目录为 Linux/macOS 的 `/opt/termiscope`，Windows 的 `C:\Program Files\TermiScope`。
- 新安装默认监听 TCP `3000`；配置模板和未指定配置时的代码默认值为 `8080`。以实际 `configs/config.yaml` 为准。
- 数据库为 SQLite，默认位于 `data/termiscope.db`。请为数据库、日志、录屏和传输临时数据预留空间。
- Linux/macOS 安装脚本需要 `tar` 和 `openssl`，在线安装还需要 `curl`。Linux 还需要 systemd，Alpine 可使用 OpenRC。
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

安装器会自动识别 `amd64`、`arm64` 或 ARMv7，下载匹配的最新包，生成强随机密钥，创建 `termiscope` 服务并启动。Debian、Ubuntu、RHEL、Rocky Linux 等 systemd 系统使用 `/etc/systemd/system/termiscope.service`；Alpine 使用 `/etc/init.d/termiscope`。

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

从 [GitHub Releases](https://github.com/ihxw/TermiScope/releases) 选择固定版本，不建议在变更窗口内使用会漂移的 `latest`。以下以 Linux amd64 的 `1.7.74` 为例：

```bash
VERSION=1.7.74
ASSET="TermiScope-${VERSION}-linux-amd64.tar.gz"
BASE_URL="https://github.com/ihxw/TermiScope/releases/download/v${VERSION}"

curl -fLO "${BASE_URL}/${ASSET}"
curl -fLO "${BASE_URL}/${ASSET}.sha256"
sha256sum -c "${ASSET}.sha256"
```

macOS 校验：

```bash
shasum -a 256 -c TermiScope-1.7.74-darwin-arm64.tar.gz.sha256
```

Windows 校验：

```powershell
$Package = 'TermiScope-1.7.74-windows-amd64.zip'
$Expected = ((Get-Content "$Package.sha256" -Raw) -split '\s+')[0].ToLowerInvariant()
$Actual = (Get-FileHash $Package -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA256 校验失败：$Package" }
"SHA256 校验通过：$Package"
```

将发布包和 `.sha256` 一起转运，并在离线目标机再次校验。不要使用 GitHub 自动生成的 `Source code` 压缩包代替 Release 资产；它不包含已构建服务端、Web 资源和 Agent。

### 5.2 Linux systemd 离线安装

```bash
tar -xzf TermiScope-1.7.74-linux-amd64.tar.gz
cd TermiScope-1.7.74-linux-amd64
sudo ./scripts/install_local.sh --install-dir /opt/termiscope --port 3000 -y
```

也可直接从压缩包安装：

```bash
sudo bash scripts/install_from_archive.sh \
  /path/to/TermiScope-1.7.74-linux-amd64.tar.gz \
  --install-dir /opt/termiscope \
  --port 3000 \
  -y
```

`install_local.sh` 只适用于 systemd。它不会覆盖已有的 `configs/config.yaml`、`data/` 和 `logs/`，因此也可用于同目录离线升级。

### 5.3 Alpine Linux 离线安装

Alpine 应运行包内通用安装器，由其配置 OpenRC：

```bash
tar -xzf TermiScope-1.7.74-linux-amd64.tar.gz
cd TermiScope-1.7.74-linux-amd64
sudo ./scripts/install.sh --install-dir /opt/termiscope --port 3000 -y
sudo rc-service termiscope status
```

### 5.4 macOS 离线安装

```bash
tar -xzf TermiScope-1.7.74-darwin-arm64.tar.gz
cd TermiScope-1.7.74-darwin-arm64
sudo ./scripts/install.sh --install-dir /opt/termiscope --port 3000 -y
sudo launchctl print system/com.termiscope.server
```

包内存在服务端和 `web/dist` 时，`install.sh` 自动进入离线模式，不会访问 GitHub。

### 5.5 Windows 离线安装

当前 Release 中的 `scripts/install.ps1` 是在线安装器，即使从解压目录运行也会访问 GitHub。完全离线的 Windows 环境应在管理员 PowerShell 中执行以下安装过程。该过程同时适用于升级，并保留已有配置和数据库。

先解压发布包：

```powershell
$Archive = 'D:\offline\TermiScope-1.7.74-windows-amd64.zip'
$ExtractDir = 'D:\offline\TermiScope-1.7.74'
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

`public_base_url` 决定 Agent 的回连地址。若 TLS 在 Nginx 终止而该配置留空，服务端可能生成错误的 `http://` 地址，表现为 Agent 安装成功但监控无数据。修改后重启 TermiScope，并重新部署受影响主机的 Agent。

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

容器部署不建议使用管理界面自升级，应重新构建镜像并重建容器，使运行状态与镜像定义保持一致。

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

### 9.1 直接运行 Release 镜像

正式发布流程在 Gitea 构建安装包后，复用 Linux 发布包生成镜像并推送到 Docker Hub 的 `iwlz/termiscope`，随后发布 GitHub Release。目标服务器直接拉取已构建的镜像，无需源码、Go、Node.js 或本地编译。

#### 9.1.1 在运行目录启动

在选定的部署运行目录执行以下命令。默认使用 Linux Docker Engine 的 host 网络，所有持久化数据都保存在当前目录：

```bash
mkdir -p data configs logs
chmod 700 configs
docker run -d --name termiscope --restart unless-stopped --network host \
  -v "$PWD/data:/app/data" \
  -v "$PWD/configs:/app/configs" \
  -v "$PWD/logs:/app/logs" \
  iwlz/termiscope:latest
```

Docker 按服务器架构选择 Linux amd64 或 arm64 镜像。访问 `http://服务器IP:3000` 完成管理员初始化；没有预设管理员密码。

| 标签 | 用途 |
| --- | --- |
| `latest` | 最新正式发布的稳定版本 |
| `v1.7.118`、`1.7.118` | 固定到对应 Release 版本，实际使用已发布的版本号 |

首次启动会自动生成独立的 JWT 与 AES 密钥，写入宿主机 `./configs/config.yaml`，对应容器内 `/app/configs/config.yaml`。无需提前创建 `.env`。镜像包含前端、服务端、各平台 Agent 和安装、卸载脚本模板。

macOS/Windows Docker Desktop 需要先启用其支持的 host 网络功能；不具备该功能时，移除 `--network host` 并添加 `-p 3000:3000`，使用 bridge 网络。相关条件见 [Docker 官方 host 网络说明](https://docs.docker.com/engine/network/drivers/host/)。

首次发布前，维护者需要在 Docker Hub 创建公开的 `termiscope` 仓库，并在 Gitea 配置推送凭据，参见第 11 节。镜像命名空间由 Docker Hub 用户名或组织名决定，GitHub 发布页面会填入实际镜像地址。仅上传 GitHub Release 安装包不会自动产生容器镜像。

#### 9.1.2 端口与反向代理

host 模式共用宿主机网络，不使用 `-p` 或 Compose `ports`。默认监听宿主机 `3000` 端口；端口被占用或需要其他端口时，在镜像名之前添加 `-e TERMISCOPE_PORT=8080`，并将访问地址、反向代理上游改为 `8080`。健康检查会使用实际的 `TERMISCOPE_PORT`。

通过 HTTPS 反向代理访问时，在镜像名称前添加公开回连地址：

```bash
docker run -d --name termiscope --restart unless-stopped --network host \
  -e TERMISCOPE_PUBLIC_BASE_URL=https://termiscope.example.com \
  -v "$PWD/data:/app/data" \
  -v "$PWD/configs:/app/configs" \
  -v "$PWD/logs:/app/logs" \
  iwlz/termiscope:latest
```

该地址用于 Agent 安装与回连；代理配置见第 7.2 节。host 模式下可直接通过宿主机地址访问目标服务。服务端监听所有本机网络接口，若只允许经反向代理访问，请通过宿主机防火墙限制应用端口的外部访问。

#### 9.1.3 管理、升级与回滚

在原部署运行目录执行：

```bash
# 查看日志和健康状态
docker logs -f termiscope
docker inspect --format '{{.State.Health.Status}}' termiscope

# 重置已有管理员的密码，将用户名替换为实际账号
docker exec -it termiscope ./main -reset-pwd 管理员用户名

# 完成备份后拉取新镜像并重建，继续挂载原目录
docker pull iwlz/termiscope:latest
docker stop termiscope
docker rm termiscope
docker run -d --name termiscope --restart unless-stopped --network host \
  -v "$PWD/data:/app/data" \
  -v "$PWD/configs:/app/configs" \
  -v "$PWD/logs:/app/logs" \
  iwlz/termiscope:latest
```

升级时保留自定义端口和环境变量。始终使用原部署目录，或在挂载参数中指定原目录的绝对路径；切换目录会创建另一套数据。容器部署通过拉取镜像并重建升级；管理界面替换容器内二进制的方式无法在下次重建时保留。回滚使用此前的版本标签，数据库或配置格式有变化时，还需恢复对应备份。

#### 9.1.4 持久化与备份

| 运行目录下的路径 | 容器路径 | 内容 |
| --- | --- | --- |
| `./data` | `/app/data` | SQLite 数据库、缓存及临时备份/传输文件 |
| `./configs` | `/app/configs` | 自动生成的密钥与配置 |
| `./logs` | `/app/logs` | 日志 |

镜像将临时目录 `TMPDIR` 设为 `/app/data`，Agent 哈希缓存保存在 `./data/agent_hashes.json`。可再生缓存在升级后会按实际 Agent 文件重新计算。

数据库和配置必须一起保留。删除或更换配置目录会丢失原 AES 密钥，导致已保存的主机凭据无法解密。删除或重建容器不会删除这些宿主机目录。

在部署运行目录停止服务后备份三个目录：

```bash
umask 077
docker stop termiscope
tar -czf "termiscope-backup-$(date +%Y%m%d-%H%M%S).tar.gz" data configs logs
# 使用 .env 提供配置或旧密钥时，还需单独备份该文件
# cp -p .env .env.backup
docker start termiscope
```

恢复时先停止服务并保留当前目录副本，再将同一次备份中的 `data`、`configs` 和 `logs` 解压回部署目录，恢复原环境变量后启动容器。备份包含密钥，应妥善保管；环境变量中的密钥优先于配置文件，也必须备份并保持原值。

#### 9.1.5 使用 Compose 或从源码构建

预构建镜像可在部署运行目录保存以下 `compose.yaml`，相对挂载路径以该文件所在目录为准：

```yaml
services:
  termiscope:
    image: iwlz/termiscope:latest
    container_name: termiscope
    restart: unless-stopped
    network_mode: host
    environment:
      TERMISCOPE_PORT: "${TERMISCOPE_PORT:-3000}"
    volumes:
      - ./data:/app/data
      - ./configs:/app/configs
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD-SHELL", "wget -q -T 4 -O /dev/null http://127.0.0.1:$${TERMISCOPE_PORT:-3000}/api/system/info || exit 1"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
```

```bash
mkdir -p data configs logs
chmod 700 configs
docker compose up -d
# 升级时保持原目录和配置
docker compose pull
docker compose up -d
```

修改监听端口时，可在同目录 `.env` 中设置 `TERMISCOPE_PORT=8080` 后重建。Docker Desktop 未启用 host 支持时，删除 `network_mode: host` 并添加 `ports: ["3000:3000"]`；若修改监听端口，需同步修改映射中的容器端口。

需要自定义源码时，在完整源码仓库根目录运行：

```bash
bash docker-deploy.sh
```

此脚本使用根目录的 `Dockerfile` 和 `docker-compose.yml` 本地构建，同样默认使用 host 网络并挂载运行目录下的 `./data`、`./configs`、`./logs`。脚本自动生成的密钥保存在运行目录的 `.env`，并通过环境变量传入容器；源码 Compose 要求填写这两个密钥。升级时保留原 `.env`、配置和数据目录，不要重新生成密钥。

源码镜像的服务端和 Agent 版本默认读取 `web/package.json`，无需另行修改 Dockerfile 或 Compose 中的版本号。更新源码后重新执行部署脚本以构建并重建容器；只运行 `docker compose restart` 会继续使用原镜像。可通过 `/api/system/info` 的 `data.version` 确认运行中的服务端版本。

#### 9.1.6 从旧命名卷迁移

旧部署示例使用 `termiscope-data`、`termiscope-config`、`termiscope-logs` 命名卷。切换到目录挂载前必须迁移数据与原配置，直接挂载空目录会初始化新实例。

准备一个新的空部署目录，在旧容器仍然存在时执行：

```bash
mkdir -p data configs logs
chmod 700 configs
# 核对旧容器实际挂载；Compose 卷名可能带项目名前缀
docker inspect --format '{{range .Mounts}}{{println .Destination .Name .Source}}{{end}}' termiscope
docker stop termiscope
docker cp termiscope:/app/data/. ./data/
docker cp termiscope:/app/configs/. ./configs/
docker cp termiscope:/app/logs/. ./logs/
umask 077
tar -czf termiscope-before-directory-migration.tar.gz data configs logs
```

检查 `./data/termiscope.db` 与原配置已复制。若旧容器通过 `.env` 或环境变量提供密钥，继续保留并注入原值，或在新容器首次启动前将原值写入 `./configs/config.yaml` 的 `security.jwt_secret` 与 `security.encryption_key`。旧部署未生成 `config.yaml` 时，先用原密钥补齐配置，或显式注入原密钥后启动；不要重新生成密钥。备份原始环境配置后，再删除旧容器，按第 9.1.1 节的 host 网络命令启动。

确认管理员登录、主机凭据、SSH 和监控正常后，再按需清理旧卷。验证完成前不要执行 `docker compose down -v` 或删除命名卷。

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

若日志出现 `Unable to locate executable file: docker`，检查 Docker 准备步骤是否运行、下载是否成功；若提示 CLI 已就绪但无法访问守护进程，需修正 Runner 的 socket 或远程连接配置。预检失败会在编译前停止，避免到登录或清理阶段才发现问题。`Dockerfile.release` 只组装已编译的 Release 内容，目标架构阶段不执行命令，因此无需 QEMU。

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
