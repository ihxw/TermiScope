# TermiScope

TermiScope 是一款面向运维场景的服务器监控与远程管理工具，包含服务端、Agent 与 Web 控制台。

本仓库用于托管 **GitHub Release 发布文件**（安装包与安装脚本）和部署说明，预构建容器镜像发布到 Docker Hub，源码不在此公开。

## 容器一条命令部署

正式发布的镜像支持 Linux amd64 和 arm64。先进入用于部署的目录，再创建持久化目录并启动容器：

```bash
mkdir -p data configs logs
docker run -d --name termiscope --restart unless-stopped --network host \
  -v "$(pwd)/data:/app/data" \
  -v "$(pwd)/configs:/app/configs" \
  -v "$(pwd)/logs:/app/logs" \
  iwlz/termiscope:latest
```

Linux 默认使用 Docker 的 `host` 网络模式，共用宿主机网络。访问 `http://服务器IP:3000` 创建管理员；需要更换端口时，在镜像名称前添加 `-e TERMISCOPE_PORT=3001`，并使用新端口访问。

Docker Desktop 需要 4.34 或更新版本，并先在设置的 `Resources > Network` 中启用 `Enable host networking`，参见 [Docker 官方说明](https://docs.docker.com/engine/network/drivers/host/)。

数据库、运行缓存和临时文件保存在执行命令时所在目录的 `./data`，配置与日志分别保存在 `./configs`、`./logs`。首次启动自动生成的密钥保存在 `./configs/config.yaml`；升级和恢复数据库时必须一起保留配置与密钥，并在原部署目录重建容器。也可将 `latest` 换成指定 Release 标签。

反向代理部署时，在镜像名称前添加 `-e TERMISCOPE_PUBLIC_BASE_URL=https://你的域名`。详细说明见 [部署手册](docs/deployment.md#91-直接运行-release-镜像)。

### Docker Compose

在部署目录创建 `compose.yaml`：

```yaml
services:
  termiscope:
    image: iwlz/termiscope:latest
    container_name: termiscope
    restart: unless-stopped
    network_mode: host
    environment:
      TERMISCOPE_PORT: "3000"
    volumes:
      - ./data:/app/data
      - ./configs:/app/configs
      - ./logs:/app/logs
```

启动与升级都在同一部署目录执行：

```bash
mkdir -p data configs logs
docker compose up -d
# 升级前先备份，再拉取并应用新镜像
docker compose pull
docker compose up -d
```

### 备份与升级

停机备份数据库、密钥和日志：

```bash
docker stop termiscope
tar -czf "termiscope-backup-$(date +%Y%m%d-%H%M%S).tar.gz" configs data logs
docker start termiscope
```

直接使用 `docker run` 的实例升级时，先备份，再执行以下命令，最后在原部署目录重新执行上方启动命令，复用原来的三个目录：

```bash
docker pull iwlz/termiscope:latest
docker stop termiscope
docker rm termiscope
```

## 下载安装

最新安装包与安装脚本见右侧 [Releases](https://github.com/ihxw/TermiScope/releases) 页面。

生产环境安装、离线校验与转运、反向代理、升级和回滚步骤见 [在线与离线部署手册](docs/deployment.md)。

| 平台 | 安装包 | 安装脚本 |
| ---- | ---- | ---- |
| Linux (amd64 / arm64 / armv7) | `TermiScope-*-linux-*.tar.gz` | `install.sh` |
| Windows (amd64 / arm64) | `TermiScope-*-windows-*.zip` | `install.ps1` |
| macOS (amd64 / arm64) | `TermiScope-*-darwin-*.tar.gz` | `install.sh` |

每个安装包均附带 `.sha256` 校验文件，请下载后先校验再安装。

## 在线部署

### Linux

```bash
curl -fsSL https://github.com/ihxw/TermiScope/releases/latest/download/install.sh \
  -o /tmp/termiscope-install.sh
sudo bash /tmp/termiscope-install.sh
```

### macOS

Intel 和 Apple Silicon 使用同一个命令，脚本自动选择架构并注册 launchd 服务：

```bash
curl -fsSL https://github.com/ihxw/TermiScope/releases/latest/download/install.sh \
  -o /tmp/termiscope-install.sh
sudo bash /tmp/termiscope-install.sh
```

Linux/macOS 默认安装到 `/opt/termiscope`，交互式选择目录、端口及密钥。无人值守安装可执行 `sudo bash /tmp/termiscope-install.sh --install-dir /opt/termiscope --port 3000 -y`。Linux 支持 systemd，Alpine 使用 OpenRC。macOS 安装器会清除下载隔离属性；当前二进制未经过 Apple 公证。

### Windows

以管理员身份打开 PowerShell：

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$script = (New-Object Net.WebClient).DownloadString('https://github.com/ihxw/TermiScope/releases/latest/download/install.ps1')
& ([scriptblock]::Create($script))
```

默认安装到 `C:\Program Files\TermiScope` 并创建开机计划任务。无人值守安装将最后一行改为 `& ([scriptblock]::Create($script)) -Y -Port 3000`。

安装后访问 `http://服务器IP:3000`，按照页面提示创建管理员。原生安装的数据、配置和日志保存在安装目录下的 `data`、`configs`、`logs`。在线安装器不读取旁路 `.sha256` 文件；需要校验发布包时使用下方离线流程。

## 离线部署

在联网机器从 [GitHub Releases](https://github.com/ihxw/TermiScope/releases) 下载与目标系统、架构匹配的正式发布包及同名 `.sha256` 文件，校验后一起转运到离线机器，并再次校验。选择 `TermiScope-<版本号>-<系统>-<架构>` 资产；GitHub 自动生成的 `Source code` 压缩包不包含运行所需的构建产物。

以下命令中的 `VERSION` 请替换为要安装的 Release 版本号（不带 `v`）；Linux ARM64 将 `amd64` 改为 `arm64`，ARMv7 使用发布资产名中的 `arm`。

### Linux

在保存发布包的目录执行：

```bash
VERSION=1.7.120
PACKAGE="TermiScope-${VERSION}-linux-amd64"
sha256sum -c "${PACKAGE}.tar.gz.sha256"
tar -xzf "${PACKAGE}.tar.gz"
cd "${PACKAGE}"
sudo bash scripts/install_local.sh --install-dir /opt/termiscope --port 3000 -y
```

Alpine 使用包内通用安装器配置 OpenRC，将最后一行改为 `sudo bash scripts/install.sh --install-dir /opt/termiscope --port 3000 -y`。安装器保留已有配置、数据库和日志，适用于同目录升级。

### macOS

Apple Silicon 示例；Intel 将 `arm64` 改为 `amd64`：

```bash
VERSION=1.7.120
PACKAGE="TermiScope-${VERSION}-darwin-arm64"
shasum -a 256 -c "${PACKAGE}.tar.gz.sha256"
tar -xzf "${PACKAGE}.tar.gz"
cd "${PACKAGE}"
sudo bash scripts/install.sh --install-dir /opt/termiscope --port 3000 -y
```

包内存在服务端和 `web/dist` 时，通用安装器自动使用本地文件，不访问 GitHub。

### Windows

在保存发布包的目录打开 PowerShell。AMD64 示例；Windows ARM64 将 `amd64` 改为 `arm64`：

```powershell
$Version = '1.7.120'
$Package = "TermiScope-$Version-windows-amd64.zip"
$Expected = ((Get-Content "$Package.sha256" -Raw) -split '\s+')[0]
if ((Get-FileHash $Package -Algorithm SHA256).Hash -ne $Expected) {
    throw 'SHA256 校验失败'
}
Expand-Archive -Path $Package -DestinationPath . -Force
Set-Location "TermiScope-$Version-windows-amd64"
$env:TERMISCOPE_PORT = '3000'
.\TermiScope.exe
```

以上命令在解压目录以前台方式运行，配置、数据和日志保存在该运行目录下，首次启动自动生成密钥并写入 `configs/config.yaml`。需要开机运行、安装到固定目录或升级现有实例时，按 [Windows 离线安装步骤](docs/deployment.md#55-windows-离线安装) 复制程序并注册计划任务，保留原 `configs`、`data`、`logs`。包内 `scripts/install.ps1` 是在线安装器，不适用于完全离线环境。

## 目录说明

- `scripts/` — 安装与卸载脚本（含 Agent 安装脚本模板）
- `configs/config.example.yaml` — 配置参考模板（真实配置包含密钥，不应公开）
- `docs/deployment.md` — 在线、离线及生产部署说明

## 安全说明

- 源码不公开，以降低被针对性挖掘漏洞的风险。
- 请始终从本仓库 Release 页面下载安装包并校验 SHA256，避免使用来路不明的二进制。
- 如发现安全问题，请通过 issue 反馈（勿公开敏感细节）。

## 许可证

[LICENSE](LICENSE)
