# Flutter/Web Parity Audit

目标：Flutter 客户端在不修改服务端 API、不修改现有 `web/` 的前提下，逐页复刻 Web 端界面与交互。

## 已对齐

- Dashboard 外壳：桌面端顶部横向导航，移动端抽屉，管理员菜单控制，后端版本与用户名显示，服务端更新检测/确认/进度弹窗已对齐 Web。
- 登录页：卡片尺寸、标题尺寸、语言/主题按钮、默认空用户名、默认不记住、2FA 信息块、错误提示与前端版本号已向 Web 对齐。
- 终端页：主机选择、新建主机、快速连接、录制下次会话工具栏已移动到终端页面卡片内。
- 主机编辑弹窗：已补齐主机类型、认证方式、私钥、远程 Shell、系统类型、分组、描述、标记、到期日期、计费周期、费用金额与币种。
- 已处理多处 Flutter Web `BOTTOM` 溢出：监控卡片、文件传输主机选择页、终端空状态、连接历史状态列。
- AntdFlutter 基础组件第一层落地（`lib/widgets/antd/`）：`AntdButton`、`AntdInput`、`AntdPasswordInput`、`AntdTextArea`、`AntdFormItem`、`AntdCard`、`AntdTag`、`AntdAlert`、`AntdEmpty`、`AntdSpin`、`AntdSpace`、`AntdDivider`，配套 `AntdTokens` 扩展与 `AntdTheme`。
- 公共流程页面（`login_screen.dart`、`setup_screen.dart`、`forgot_password_screen.dart`、`reset_password_screen.dart`、`auth_scaffold.dart`）已迁移到 Antd 基础组件：按钮高度、输入框边框/focus 颜色、错误/信息 Alert、密码显隐切换均向 Web ant-design-vue 对齐，不再直接出现 `ElevatedButton`、`OutlinedButton`、`TextField` 等 Material 风格控件。
- AntdFlutter 阶段 2 落地：`AntdToolbar`、`AntdTabs`（含 editor 模式）、`AntdDropdown`、`AntdModal`、`AntdSwitch`、`AntdSelect`、`AntdRadioGroup`。
- 终端页 `terminal_tabs_screen.dart` 工具栏迁至 `AntdToolbar`+`AntdSelect`+`AntdButton`+`AntdSwitch`，tab 条迁至 `AntdTabs(editor: true)`，录制红点/关闭/选中色完整对齐。
- 主机编辑 `host_edit_dialog.dart` 迁至 `AntdModal`+`AntdInput`+`AntdSelect`+`AntdRadioGroup`+`AntdFormItem`+`AntdDivider`；弹窗圆角 8、标题栏+关闭、字段序列与 Web 保持一致。
- 首页 `home_screen.dart` 顶部用户菜单迁至 `AntdDropdown`，语言/主题按钮迁至 `AntdButton(link/text)`，移除未使用的终端工具栏方法。
- AntdFlutter 阶段 3 落地：`AntdTable`（固定列宽/横向滚动/行选择/loading/empty/行悬浮）、`AntdPagination`、`AntdActionMenu`（行操作弹出菜单）、`AntdStatusBadge`。
- 主机管理 `host_management_screen.dart` 从卡片列表迁至 `AntdTable` 表格结构，列对齐 Web：名称（图标+名称）、状态（在线/离线圆点）、监控（Tag）、描述（主机地址）、类型（Tag）、到期日期、计费周期、操作（ActionMenu 中含测试连接/部署监控/停止监控/编辑/删除）。搜索框和快速过滤改用 `AntdInput`+`AntdRadioGroup`。删除确认改用 `AntdModal(danger)`。
- AntdFlutter 阶段 4 落地：`AntdSegmented`（卡片/列表切换）、`AntdProgress`（进度条+环形进度）、`AntdPopover`（点击弹出层）、`AntdMetricCard`（监控指标卡片：大数值+图标+状态+操作按钮+内嵌内容）。
- 监控 `monitor_tab.dart` 添加卡片/列表模式切换（`AntdSegmented`），卡片迁至 `AntdMetricCard`（CPU/RAM/DISK 用 `AntdProgress`，流量/到期/计费信息保留），每卡配操作按钮（网络/历史/设置）。
- AntdFlutter 阶段 5 落地：`AntdUploadProgressDock`（上传进度底栏）、`AntdConflictModal`（文件冲突弹窗）、`AntdFileList`（SFTP 文件列表组件）、`AntdSplitPane`（可拖拽分割面板）。
- SFTP `file_transfer_screen.dart` 已按 Web 改为双主机双面板：桌面左右布局、移动端上下布局、独立路径导航、服务器端历史/收藏、多选与批量跨主机传输均已接入。
- SFTP 上传、下载、文本编辑保存、同名覆盖/保留两份和 NDJSON 传输进度已接入真实 API；上传/下载/跨主机任务统一显示在进度 Dock。
- SFTP 媒体预览已对齐 Web：图片支持缩放查看（含 SVG），视频使用跨 Windows/Web/移动端播放器并携带现有鉴权头流式播放。
- SFTP 剪切/复制/粘贴已对齐 Web：支持单项与批量、同主机 paste API、跨主机流式 transfer、冲突覆盖/保留两份以及 cut 后源目录刷新。
- SFTP 工具栏已补齐拖放上传、批量下载/删除、全选/反选/清空、所选属性统计；传输 Dock 已接入真实请求取消、失败/取消重试和完成任务清理。
- SFTP 文本编辑已从单文件模态框升级为常驻多标签编辑器，支持脏状态、保存、重新加载、查找替换、最小化/最大化、关闭确认和 `Ctrl/Cmd+S`。
- AntdFlutter 文件工作流组件已扩展：`AntdInput` 支持填充式代码编辑，新增 `AntdMediaPreview`，`AntdUploadProgressDock` 支持取消/重试动作。
- 终端会话中的 SFTP 按钮已接入当前主机的真实分屏，桌面端左右分栏、窄屏上下分栏；分栏支持拖拽和比例持久化，并跟随终端 `cd` 后的当前目录。
- 终端多标签会话通过 `IndexedStack` 常驻，切换标签不再销毁 SSH 会话；异常断开自动重连，右键复制/粘贴、`Alt+K`、数字快捷键和命令模板 `auto_enter` 已接入。
- 主机管理已补完整 Host 数据模型，编辑不再用默认认证/Shell/系统值覆盖原数据；主动连接状态检测、已删除主机、彻底删除、批量部署/停止、批量通知和孤立 Agent 提示已接入。
- 主机管理响应式表格已继续对齐 Web：桌面补齐端口/用户名/分组等信息列，移动端精简为核心列和统一操作菜单；删除状态、加载失败重试、搜索范围、到期/剩余价值、批量确认与排序约束已完善，连接测试不再把 HTTP 200 的离线结果误判在线。
- 主机监控管理已补齐真实 Linux/macOS/Windows 安装命令、手动卸载命令和复制操作；自动/批量部署支持现有 `insecure` 合约并增加确认提示。
- `AntdTable` 已补齐表头全选/半选、不可选行和表头/表体横向滚动同步；`AntdDropdown` 已支持禁用菜单项。
- `AntdModal` 已支持异步确认操作的自动加载态和重复提交保护，空取消文案不再生成占位按钮；用户、命令模板、监控模板、系统维护、录制管理和监控排序弹窗均在操作成功后关闭，失败时保留现场供重试。
- 监控模板编辑已统一使用本地 `AntdSelect`，部署时过滤纯监控主机、无可用主机时禁用确认，并兼容后端返回的通用数值 ID。
- 监控页列表模式已改为真实表格；断线提示、Agent 版本/单个及批量更新、CPU/磁盘明细、流量重置日期、视图持久化、排序以及状态/重置日志分页重试已接入。
- 监控页工具栏已移除会导致整页空白的非法 Flex 子组件，并按 Web 改为全宽、左对齐、可换行布局；公共 `AntdToolbar` 同步改为按父容器实际宽度铺满，修复各页面二级栏在宽屏居中且最多 1200px 的问题。
- 监控卡片已复刻 Web 的 `height: 100%` 网格行为：同一响应式网格行按内容最高卡片统一高度，流量和到期/计费长文本在五列及窄屏布局下自适应收缩，不再溢出。
- 连通性监控时间轴与 Web 对齐：历史覆盖达到所选范围 80% 时保留完整范围，稀疏或新任务数据自动贴合实际时间并保留小幅边距。
- Windows x86_64 发布构建已接入 GitHub Actions；每次 `mobile/flutter_app` 改动都会生成可下载 ZIP 构建产物。

## 页面级差异清单

| Web 页面/组件 | Flutter 对应 | 当前状态 | 主要差异 |
| --- | --- | --- | --- |
| `Login.vue` | `login_screen.dart` | 基本对齐 | 已迁移到 Antd 基础组件；仍保留服务器地址字段以支持 Flutter 独立运行 |
| `Setup.vue` | `setup_screen.dart` | 基本对齐 | 已迁移到 Antd 基础组件；首次无服务地址时仍需手动输入服务器主页 |
| `ForgotPassword.vue` | `forgot_password_screen.dart` | 基本对齐 | 已迁移到 Antd 基础组件；保留 Flutter 独立运行所需的服务器地址字段 |
| `ResetPassword.vue` | `reset_password_screen.dart` | 基本对齐 | 已迁移到 Antd 基础组件；保留 Flutter 独立运行所需的服务器地址字段 |
| `Dashboard.vue` | `home_screen.dart` | 基本对齐 | 顶部导航/下拉用户菜单已迁移到 AntdDropdown/AntdButton；更新检测、升级确认、升级进度弹窗已移植 |
| `Terminal.vue` | `terminal_tabs_screen.dart` + `terminal_session_screen.dart` | 基本对齐 | 工具栏、常驻多会话 tab、自动重连、命令快捷键/自动回车、主题/字体、可调 SFTP 分屏、指纹确认和重复会话选择均已接入 |
| `components/Terminal.vue` | `terminal_session_screen.dart` | 基本对齐 | 桌面右键复制/粘贴和 WebLinks 已接入；移动端保留专用虚拟键盘 |
| `MonitorDashboard.vue` | `monitor_tab.dart` | 基本对齐 | 卡片/真实表格模式、全宽左对齐工具栏、断线提示、Agent 更新、CPU/磁盘明细、流量/财务、排序、分页状态历史和流量重置日志已接入 |
| `NetworkDetail.vue` | `network_detail_screen.dart` | 基本对齐 | 网络详情、连通性（Ping折线/平滑图表及自适应时间轴）、网卡配置、网卡接口、告警通知均已对齐。 |
| `monitor/MonitorTemplates.vue` | `monitor_templates_screen.dart` | 基本对齐 | 监控模板管理表格、模板表单编辑/添加/删除、部署弹窗分配主机均已对齐。 |
| `HostManagement.vue` | `host_management_screen.dart` + `host_edit_dialog.dart` | 基本对齐 | 完整字段编辑保真、主动状态检测、已删除/彻底删除、批量部署/停止/通知、孤立 Agent 提示、选择和排序已接入 |
| `ConnectionHistory.vue` | `connection_history_screen.dart` | 基本对齐 | 已迁到 AntdToolbar+AntdSelect+AntdSpin+AntdEmpty+AntdTag；主机过滤下拉、状态标签、时长格式对齐 Web |
| `CommandManagement.vue` | `command_templates_screen.dart` | 基本对齐 | 已迁到 AntdToolbar+AntdModal+AntdFormItem+AntdInput+AntdButton；复制/编辑/删除操作对齐 Web |
| `UserManagement.vue` | `user_management_screen.dart` | 基本对齐 | 已迁到 AntdTable（用户名/角色/显示名/邮箱/状态开关/操作菜单）+AntdModal；编辑/删除/重置密码弹窗对齐 Web |
| `Profile.vue` | `profile_screen.dart` | 基本对齐 | 已迁到 AntdTabs+AntdFormItem+AntdPasswordInput+AntdStatusBadge；安全/会话分页、密码修改、2FA 状态标签对齐 Web |
| `SystemManagement.vue` | `system_management_screen.dart` | 基本对齐 | Tab 迁到 AntdTabs，所有弹窗迁到 AntdModal，表单迁到 AntdInput/AntdFormItem，按钮迁到 AntdButton；备份/清理/模板部署保持原逻辑 |
| `RecordingManagement.vue` | `recording_management_screen.dart` | 基本对齐 | 已迁到 AntdToolbar+AntdCard+AntdModal+AntdButton；播放弹窗、删除确认对齐 Web |
| `FileTransfer.vue` + SFTP components | `file_transfer_screen.dart` + `sftp_service.dart` | 已对齐 | 双主机面板、媒体预览、常驻多标签文本编辑、上传/下载、剪切/复制/粘贴、单项/批量跨主机传输、拖放、批量选择操作、冲突处理、可取消/重试进度 Dock、服务器历史/收藏均已接入 |

## 下一批优先级

1. 终端页继续走查录制会话和移动端虚拟键盘的边界状态。
2. 监控页在真实后端数据下继续做卡片高度和窄屏表格的像素级校验。
3. 主机管理继续做桌面/移动端排序和超长主机名的视觉走查。
4. 公共流程继续做中英文文案和像素级视觉走查。
