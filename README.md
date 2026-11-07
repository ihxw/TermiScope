# TermiScope

TermiScope 是一款面向运维场景的服务器监控与远程管理工具，包含服务端、Agent 与 Web 控制台。

本仓库用于托管 **GitHub Release 发布文件**（安装包与安装脚本）和部署说明，预构建容器镜像发布到 Docker Hub，源码不在此公开。

服务端（含 Web 和 Agent）使用 `vX.Y.Z` 发行及 `TermiScope-<版本>-<系统>-<架构>` 安装包；本地客户端单独使用 `client-vX.Y.Z` 发行及 `TermiScope-Client-<版本>-<平台>` 安装包。两者分别更新，版本号无需相同。在线安装器与 Docker `latest` 继续指向服务端；客户端下载不会替换服务器。

## Docker + PostgreSQL 容器部署

推荐使用独立 PostgreSQL 17 Alpine 与应用容器。默认 bridge 网络仅发布 Web 端口，数据库不映射到宿主机；最低1核1GB适合小规模实例，较多监控任务建议2核2GB以上。默认限制连接池与内存，不承诺任意负载下没有瓶颈。

正式 Release 提供已固定版本的 `TermiScope-Docker.tar.gz` 和 `.sha256`。在固定目录下载、校验并解压后运行：

```bash
bash docker-deploy.sh up
```

本公开仓库不提供源码；请使用 Release 部署包与对应镜像。脚本仅为全新部署生成 `.env`，已有密钥不自动重生。首次访问 `http://服务器IP:3000` 创建管理员。

已有 SQLite 实例先停止旧服务、保存数据库与配置备份，填入原 JWT/AES 密钥，再执行：

```bash
bash docker-deploy.sh migrate-sqlite /旧安装目录/data/termiscope.db --source-stopped
bash docker-deploy.sh up
```

迁移源只读，目标必须为空；不要先在新库创建管理员。数据库保存在固定命名卷 `termiscope-postgres-data`，应用文件位于 `data/`、`configs/`、`logs/`，原密钥保存在 `.env`。应用容器没有宿主机防火墙管理权限。

```bash
bash docker-deploy.sh status
bash docker-deploy.sh logs --tail 100
bash docker-deploy.sh backup
bash docker-deploy.sh restore /备份目录/database.dump
# 恢复完成后核对原密钥与应用文件，再执行 up
```

部署、1核1GB参数、迁移、备份和升级细节见[部署手册](docs/deployment.md#91-docker--postgresql-部署)。容器升级通过更改镜像版本并重建完成，保留原部署目录和 `.env`。

### 监控公开地址（HTTPS 反向代理必读）

部署监控前，必须指定被监控主机能访问的服务端完整地址。HTTPS 在 Nginx、Caddy 或其他反向代理处终止时，后端收到的是 HTTP 请求；未配置公开地址可能使 Agent 使用错误的 `http://` 地址，表现为“部署成功，但监控一直离线”。“部署成功”只表示安装及服务启动命令成功，不代表服务端已收到心跳。

容器部署不需要在宿主机创建 `config.yaml`。使用配套 Compose 时，编辑**原部署目录**的 `.env`，填写对外的 HTTPS 地址（如使用非默认端口，也要写入端口）：

```dotenv
TERMISCOPE_PUBLIC_BASE_URL=https://termiscope.example.com
```

保留现有镜像、数据库和密钥设置，在同一目录重新创建应用容器：

```bash
docker compose up -d --no-deps --force-recreate termiscope
docker exec termiscope printenv TERMISCOPE_PUBLIC_BASE_URL
```

仅执行 `docker restart` 不会应用新环境变量。1Panel、Portainer 等面板用户应在原应用容器配置中添加同名环境变量，并保留原数据挂载后重新部署。

**之后必须从新服务端重新部署受影响主机的监控 Agent**；仅监控主机需重新获取并执行安装命令。已有 Agent 不会自动更新上报地址。不要填 `localhost`、容器内部地址，或被监控主机无法访问的域名；应先确认目标主机能解析域名并访问其 HTTPS 端口。

非空 `TERMISCOPE_PUBLIC_BASE_URL` 优先于系统设置和配置文件；未使用此环境变量时，可在新版「系统管理 → 常规 → 公开访问地址」保存地址后重新部署 Agent。填写示例地址时请替换为自己的真实域名。

### 完整 docker-compose.yaml 示例

下面的配置与 `v1.7.135` 部署包一致，使用已发布的双架构镜像，适用于安装了 Docker Compose v2 的全新部署。将以下内容保存为固定部署目录中的 `docker-compose.yaml`：

已有 SQLite 或 PostgreSQL 实例请继续使用上一节的部署包管理脚本，保留原密钥并按迁移或升级步骤操作。直接运行 Compose 不执行管理脚本的旧库、丢卷和部署目录保护检查。

```yaml
name: ${COMPOSE_PROJECT_NAME:-termiscope}

services:
  postgres:
    image: postgres:17-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${TERMISCOPE_DB_NAME:-termiscope}
      POSTGRES_USER: ${TERMISCOPE_DB_USER:-termiscope}
      POSTGRES_PASSWORD: ${TERMISCOPE_DB_PASSWORD:?请配置数据库密码；全新部署可运行 scripts/docker_deploy.sh}
      POSTGRES_INITDB_ARGS: --encoding=UTF8 --locale=C.UTF-8 --data-checksums
    command:
      - postgres
      - -c
      - max_connections=${TERMISCOPE_PG_MAX_CONNECTIONS:-24}
      - -c
      - shared_buffers=${TERMISCOPE_PG_SHARED_BUFFERS:-64MB}
      - -c
      - work_mem=${TERMISCOPE_PG_WORK_MEM:-2MB}
      - -c
      - maintenance_work_mem=${TERMISCOPE_PG_MAINTENANCE_WORK_MEM:-32MB}
      - -c
      - max_wal_size=${TERMISCOPE_PG_MAX_WAL_SIZE:-512MB}
      - -c
      - effective_cache_size=${TERMISCOPE_PG_EFFECTIVE_CACHE_SIZE:-256MB}
      - -c
      - log_min_duration_statement=${TERMISCOPE_PG_SLOW_QUERY_MS:-1000}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks: [database]
    mem_limit: ${TERMISCOPE_PG_MEMORY_LIMIT:-384m}
    shm_size: 128mb
    stop_grace_period: 60s
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \"$${POSTGRES_USER}\" -d \"$${POSTGRES_DB}\""]
      interval: 5s
      timeout: 5s
      start_period: 30s
      retries: 12
    logging:
      driver: json-file
      options: {max-size: "10m", max-file: "3"}

  termiscope:
    image: ${TERMISCOPE_IMAGE:-iwlz/termiscope:v1.7.135}
    pull_policy: ${TERMISCOPE_PULL_POLICY:-always}
    container_name: termiscope
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "${TERMISCOPE_BIND_ADDRESS:-0.0.0.0}:${TERMISCOPE_PORT:-3000}:3000"
    networks: [default, database]
    # 运行层只复用 PostgreSQL 客户端，不为应用创建未使用的数据库匿名卷。
    tmpfs:
      - /var/lib/postgresql/data:size=1m,mode=0700
    volumes:
      - ./data:/app/data
      - ./configs:/app/configs
      - ./logs:/app/logs
    environment:
      TERMISCOPE_PORT: "3000"
      TERMISCOPE_DB_DRIVER: postgres
      TERMISCOPE_DB_HOST: postgres
      TERMISCOPE_DB_PORT: "5432"
      TERMISCOPE_DB_NAME: ${TERMISCOPE_DB_NAME:-termiscope}
      TERMISCOPE_DB_USER: ${TERMISCOPE_DB_USER:-termiscope}
      TERMISCOPE_DB_PASSWORD: ${TERMISCOPE_DB_PASSWORD:?请配置 TERMISCOPE_DB_PASSWORD}
      TERMISCOPE_DB_SSLMODE: disable
      TERMISCOPE_DB_MAX_OPEN_CONNS: ${TERMISCOPE_DB_MAX_OPEN_CONNS:-12}
      TERMISCOPE_DB_MAX_IDLE_CONNS: ${TERMISCOPE_DB_MAX_IDLE_CONNS:-3}
      TERMISCOPE_JWT_SECRET: ${TERMISCOPE_JWT_SECRET:?请配置原有 JWT 密钥；全新部署可运行 scripts/docker_deploy.sh}
      TERMISCOPE_ENCRYPTION_KEY: ${TERMISCOPE_ENCRYPTION_KEY:?请配置原有32字节加密密钥；全新部署可运行 scripts/docker_deploy.sh}
      TERMISCOPE_PUBLIC_BASE_URL: ${TERMISCOPE_PUBLIC_BASE_URL:-}
      TERMISCOPE_LOG_STDOUT: ${TERMISCOPE_LOG_STDOUT:-true}
      TMPDIR: /app/data
      GOMEMLIMIT: ${TERMISCOPE_GO_MEMORY_LIMIT:-256MiB}
      GOMAXPROCS: ${TERMISCOPE_GO_MAX_PROCS:-1}
    healthcheck:
      test: ["CMD-SHELL", "wget -q -T 4 -O /dev/null http://127.0.0.1:3000/api/health/ready || exit 1"]
      interval: 15s
      timeout: 5s
      start_period: 30s
      retries: 3
    mem_limit: ${TERMISCOPE_APP_MEMORY_LIMIT:-384m}
    stop_grace_period: 30s
    logging:
      driver: json-file
      options: {max-size: "10m", max-file: "3"}

networks:
  database:
    internal: true

volumes:
  postgres-data:
    name: ${COMPOSE_PROJECT_NAME:-termiscope}-postgres-data
```

在同一个目录生成配套的 `.env`。以下命令仅用于全新部署，拒绝覆盖已有 `.env`；数据库密码与 JWT 密钥各为 64 个十六进制字符，AES 密钥为恰好 32 个字符：

```bash
(
  set -eu
  umask 077
  set -C
  compose_db_password=$(openssl rand -hex 32)
  compose_jwt_secret=$(openssl rand -hex 32)
  compose_encryption_key=$(openssl rand -hex 16)
  cat > .env <<EOF
COMPOSE_PROJECT_NAME=termiscope
TERMISCOPE_BIND_ADDRESS=0.0.0.0
TERMISCOPE_PORT=3000
TERMISCOPE_DB_NAME=termiscope
TERMISCOPE_DB_USER=termiscope
TERMISCOPE_DB_PASSWORD=${compose_db_password}
TERMISCOPE_JWT_SECRET=${compose_jwt_secret}
TERMISCOPE_ENCRYPTION_KEY=${compose_encryption_key}
EOF
)
```

需要自定义端口时修改 `.env` 中的 `TERMISCOPE_PORT`；反向代理运行在宿主机时可将 `TERMISCOPE_BIND_ADDRESS` 改为 `127.0.0.1`。其余内存和连接池参数使用 Compose 文件中的默认值。已初始化数据库的密码不会随 `.env` 修改而自动改变。

检查配置并启动：

```bash
mkdir -p data configs logs
docker compose -f docker-compose.yaml config --quiet
docker compose -f docker-compose.yaml pull
docker compose -f docker-compose.yaml up -d --wait --wait-timeout 180
docker compose -f docker-compose.yaml ps
```

首次访问 `http://服务器IP:3000` 创建管理员。升级或重建时保留 `.env`、项目名、`termiscope-postgres-data` 数据卷和三个应用目录；不要运行会删除数据库卷的 `docker compose down -v`。

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

Linux/macOS 默认安装到 `/opt/termiscope`，交互式选择目录、端口及密钥。无人值守安装可执行 `sudo bash /tmp/termiscope-install.sh --install-dir /opt/termiscope --port 3000 -y`。Linux 在线、离线安装均按实际环境选择 systemd 或 OpenRC；在线依赖支持 `apt-get`、`dnf`、`yum`、`microdnf`、`apk`、`pacman`、`zypper`。Alpine 等精简系统需先准备 Bash、curl 和 CA 证书，详见[Linux 部署说明](docs/deployment.md#41-linux)。macOS 安装器会清除下载隔离属性；当前二进制未经过 Apple 公证。

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
VERSION=1.7.135
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
VERSION=1.7.135
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
$Version = '1.7.135'
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
