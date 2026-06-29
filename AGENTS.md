# Repository Guidelines

## 项目结构与模块组织

TermiScope 是 Go 后端加 Vue 3/Vite 前端的项目。后端入口位于 `cmd/server` 和 `cmd/agent`；共享后端代码位于 `internal/`，包括 `handlers`、`database`、`firewall`、`middleware`、`models`、`ssh` 等包。Web 客户端位于 `web/`，源码在 `web/src`，静态资源在 `web/public`，构建产物在 `web/dist`。API 文档生成在 `docs/`。端到端测试位于 `e2e-tests/`。安装、部署、修复和发布脚本位于 `scripts/`；Docker 相关文件位于仓库根目录和 `test-lab/`。

## 构建、测试与开发命令

- `go test ./...`：运行全部 Go 单元测试。
- `go build ./cmd/server`：构建服务端二进制。
- `go build ./cmd/agent`：构建 Agent 二进制。
- `cd web && npm run dev`：启动 Vite 前端开发服务器。
- `cd web && npm run build`：构建生产前端资源。
- `cd web && npm run preview`：本地预览前端构建产物。
- `cd e2e-tests && npm test`：运行 `runner.js` 中的 Node E2E 测试。
- `bash scripts/build_linux_amd64.sh`：生成 Linux amd64 发布包。

## 编码风格与命名约定

Go 代码必须使用 `gofmt` 格式化；包名保持简短、小写，并与目录职责一致。平台相关代码使用 Go 文件后缀区分，例如 `_linux.go`、`_windows.go`、`_stub.go`；测试文件使用 `_test.go`。Vue 代码遵循现有 Composition API 风格，单文件组件使用 PascalCase，例如 `Terminal.vue`；JavaScript 模块使用 camelCase，例如 `apiBase.js`、`useMonitorStream.js`。前端状态放在 `web/src/stores`，API 封装放在 `web/src/api`，可复用逻辑放在 `web/src/composables` 或 `web/src/utils`。

## 测试指南

Go 单元测试应靠近被测试包，命名参考现有文件，例如 `rules_expand_test.go` 和 `network_task_etag_test.go`。涉及 UI 或 API 流程的测试优先补充到 `e2e-tests/runner.js`，使用程序化断言；`TEST_INFRA.md` 说明了当前 49 个 E2E 用例的覆盖分层目标。提交前请至少运行 `go test ./...`，并根据改动范围运行相关前端或 E2E 测试。

## 提交与 Pull Request 规范

近期提交历史采用简洁的祈使句描述，必要时使用 `fix:` 或 `feat:` 前缀，例如 `fix: 修复Web界面整页滚动并更新版本号至 1.6.15`，也可使用英文描述如 `Optimize agent metric pulses and fix terminal viewport behavior`。每个提交聚焦一个逻辑变更。PR 应包含简短摘要、测试结果、关联 issue；涉及可见 UI 改动时附截图或录屏。

## 安全与配置提示

不要提交生产密钥、数据库文件、日志或生成的发布产物。以 `configs/config.example.yaml` 作为配置参考；JWT 密钥、加密密钥等敏感值应通过环境或部署配置注入，避免进入源码仓库。
