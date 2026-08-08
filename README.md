# TermiScope

TermiScope 是一款面向运维场景的服务器监控与远程管理工具，包含服务端、Agent 与 Web 控制台。

本仓库仅用于托管 **GitHub Release 发布文件**（安装包与安装脚本），源码不在此公开。

## 下载安装

最新安装包与安装脚本见右侧 [Releases](https://github.com/ihxw/TermiScope/releases) 页面。

| 平台 | 安装包 | 安装脚本 |
| ---- | ---- | ---- |
| Linux (amd64 / arm64 / armv7) | `termiscope-linux-*.tar.gz` | `scripts/install.sh` |
| Windows (amd64 / arm64) | `termiscope-windows-*.zip` | `scripts/install.ps1` |
| macOS (amd64 / arm64) | `termiscope-darwin-*.tar.gz` | `scripts/install.sh` |

每个安装包均附带 `.sha256` 校验文件，请下载后先校验再安装。

## 目录说明

- `scripts/` — 安装与卸载脚本（含 Agent 安装脚本模板）
- `configs/config.example.yaml` — 配置参考模板（真实配置包含密钥，不应公开）

## 安全说明

- 源码不公开，以降低被针对性挖掘漏洞的风险。
- 请始终从本仓库 Release 页面下载安装包并校验 SHA256，避免使用来路不明的二进制。
- 如发现安全问题，请通过 issue 反馈（勿公开敏感细节）。

## 许可证

[LICENSE](LICENSE)
