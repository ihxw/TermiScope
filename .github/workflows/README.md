## 功能

当 `web/package.json` 的 `version` 字段变更时,自动创建 Git tag,触发完整的构建和发布流程。

## 工作流程

1. **触发条件**: push到main分支且修改了`web/package.json`
2. **检查版本**: 比较当前commit和上一个commit的version字段
3. **自动构建**: 如果版本变更,直接执行完整构建流程:
   - 构建前端 (npm)
   - 构建后端 (Go)
   - 打包所有平台的二进制文件
4. **创建Release**: 创建tag并发布GitHub Release,上传构建产物

## 使用方法

1. **更新版本号**:
   ```bash
   # 修改 web/package.json 中的 version 字段
   # 例如: "version": "2.0.10"
   ```

2. **提交并推送到main分支**:
   ```bash
   git add web/package.json
   git commit -m "Bump version to 2.0.10"
   git push origin main
   ```

3. **自动完成**:
   - ✅ 自动检测版本变更
   - ✅ 自动创建tag (v2.0.10)
   - ✅ 自动触发构建流程
   - ✅ 自动创建Release并上传构建产物

## 自建 Runner 环境要求

工作流使用 `runs-on: self-hosted`，发布前请在 Runner 机器上满足：

| 工具 | 用途 | 说明 |
| --- | --- | --- |
| **Go** | 编译后端/Agent | 由 `actions/setup-go` 按 `go.mod` 安装（当前需 **≥ 1.25.5**） |
| **Node.js 20** | 前端构建、版本读取 | 由 `actions/setup-node` 安装 |
| **npm** | 随 Node 安装 | 用于 `web/` 下 `npm install && npm run build` |
| **bash** | 执行 `build_release.sh` | Linux 自带；Windows 需 Git for Windows |
| **tar** | Linux/macOS 打包 | Linux: `apt install tar` |
| **zip** | Windows 打包 | Linux Runner: `apt install zip`；Windows 建议使用 Git Bash 自带的 `zip` |
| **git** | 检出与 auto-release 打 tag | 通常已安装 |
| **bash** | 构建、打 tag、写 Release 说明 | Linux 自带即可，**无需 PowerShell** |

### 在 Runner 上预检

```bash
# 检出仓库后
bash scripts/ci/verify_release_env.sh
```

### Linux 自建 Runner 预装系统包（推荐）

在 Runner **主机上**执行一次（交互式 sudo），workflow 里不会再要密码：

```bash
sudo apt-get update
sudo apt-get install -y zip tar
```

或配置 **免密 sudo** 后，workflow 中的 `install_release_deps.sh` 才能自动安装。

`install_release_deps.sh` 仅安装 `zip`、`tar`（不再安装 `jq`）；无免密 sudo 时会跳过安装并由后续 `verify_release_env.sh` 报错。

### 常见问题

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `Go is not installed` | PATH 未生效或未跑 setup-go | 确认 workflow 中有 `actions/setup-go`，且 `go-version-file: go.mod` |
| `go: requires go >= 1.25.5` | Runner 上 Go 版本过旧 | 使用 setup-go 或手动安装 Go 1.25.5+ |
| `npm is not installed` | 未跑 setup-node | 确认 `actions/setup-node` 在 Build 之前 |
| `zip: command not found` | Linux 未装 zip | 在 Runner 主机执行 `sudo apt install zip tar` |
| `sudo: a password is required` | CI 无法交互输入密码 | 在主机预装 zip/tar，或配置 NOPASSWD sudo |
| `pwsh: not found` | 旧版 workflow 使用 PowerShell | 拉取最新 workflow（已改为 bash） |

## 注意事项

- 只需更新 `web/package.json` 的version字段
- 不需要手动创建tag或运行 `github-release.ps1`
- 确保每次版本号都是递增的
- Tag格式: `v{major}.{minor}.{patch}` (例如: v2.0.10)
- 推荐在 **Linux** 自建 Runner 上构建；Windows Runner 需已安装 Git Bash 且 `zip` 在 PATH 中

## 优势

- ✅ 版本号统一管理在package.json
- ✅ 自动检测重复tag
- ✅ 完整的构建和打包流程
- ✅ 自动上传所有平台的二进制文件
- ✅ 无需手动操作

## 示例

```bash
# 旧流程 (手动)
1. 修改 web/package.json version
2. 修改 github-release.ps1 中的tag
3. 运行 .\github-release.ps1
4. 等待release.yml构建

# 新流程 (自动)
1. 修改 web/package.json version
2. git commit && git push
3. 等待自动构建完成
```

## 禁用自动发布

如果需要临时禁用自动发布,可以:
- 删除或重命名 `.github/workflows/auto-release.yml`
