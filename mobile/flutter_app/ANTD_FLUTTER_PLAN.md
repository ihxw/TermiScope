# AntdFlutter 基础组件规划

本文档用于指导 TermiScope Flutter 客户端建立一层自有的 Ant Design 风格基础组件。目标不是引入一个“看起来差不多”的第三方库，而是在 Flutter 中复刻当前 Web 端 Ant Design Vue 的视觉、布局和交互规律，让后续页面迁移有统一底座。

## 目标与边界

### 目标

- 复刻 Web 端 Ant Design Vue 的核心视觉语言：颜色、字号、行高、边框、圆角、阴影、密度、间距、暗色模式。
- 为 Flutter 页面提供统一基础组件，减少直接使用 `ElevatedButton`、`TextField`、`Card`、`AlertDialog`、`ListTile` 造成的 Material 风格偏差。
- 支持 Web 端现有后台页面的主要形态：工具栏、卡片、表格、表单、弹窗、抽屉、标签、告警、分页、空状态、加载状态。
- 不修改服务端 API，不修改现有 `web/` 端。
- 允许内部组合 Flutter 原生组件或局部第三方包，但对页面暴露统一的 `Antd*` 组件接口。

### 非目标

- 不追求实现完整 Ant Design 组件库。
- 不追求完全兼容 Ant Design Vue 的 API 命名。
- 不在第一阶段引入复杂动画、拖拽表格、虚拟列表等高复杂能力。
- 不把所有页面一次性重写，采用逐页替换策略。

## 目录规划

建议新增如下结构：

```text
lib/
  app/
    antd_tokens.dart
    antd_theme.dart
  widgets/
    antd/
      antd_alert.dart
      antd_button.dart
      antd_card.dart
      antd_checkbox.dart
      antd_divider.dart
      antd_dropdown.dart
      antd_empty.dart
      antd_form.dart
      antd_input.dart
      antd_modal.dart
      antd_pagination.dart
      antd_radio.dart
      antd_select.dart
      antd_space.dart
      antd_spin.dart
      antd_switch.dart
      antd_table.dart
      antd_tabs.dart
      antd_tag.dart
      antd_toolbar.dart
      index.dart
```

`antd_tokens.dart` 保留为设计 token 的来源。`antd_theme.dart` 用于把 token 组织成组件主题，例如按钮高度、表格行高、弹窗宽度等。`widgets/antd/index.dart` 统一导出组件，页面只从这里引入。

## Token 设计

当前已有 `AntdTokens`，需要扩展为更接近 Ant Design 的分层 token。

### 颜色

- `colorPrimary`: `#1890ff`
- `colorSuccess`: `#52c41a`
- `colorWarning`: `#faad14`
- `colorError`: `#ff4d4f`
- `colorText`: light `#000000d9`，dark `#ffffffd9`
- `colorTextSecondary`: `#8c8c8c`
- `colorTextDisabled`: light `#00000040`，dark `#ffffff40`
- `colorBgLayout`: light `#f0f2f5`，dark `#141414`
- `colorBgContainer`: light `#ffffff`，dark `#1f1f1f`
- `colorBorder`: light `#d9d9d9`，dark `#303030`
- `colorBorderSecondary`: light `#f0f0f0`，dark `#303030`

### 尺寸与密度

- `fontSize`: `14`
- `fontSizeSM`: `12`
- `fontSizeLG`: `16`
- `lineHeight`: `1.5715`
- `borderRadius`: `2`
- `borderRadiusLG`: `8`
- `controlHeightSM`: `24`
- `controlHeight`: `32`
- `controlHeightLG`: `40`
- `paddingXS`: `4`
- `paddingSM`: `8`
- `padding`: `12`
- `paddingLG`: `16`
- `marginXS`: `4`
- `marginSM`: `8`
- `margin`: `12`
- `marginLG`: `16`

### 页面级常量

- `headerHeight`: `48`
- `contentPaddingDesktop`: `8`
- `contentPaddingMobile`: `8`
- `tableHeaderHeight`: `38`
- `tableRowHeight`: `46`
- `cardHeaderHeight`: `40`
- `modalWidth`: `520`

## 组件分层

### 第一层：基础展示组件

优先级最高，先建这些组件可以快速把页面从 Material 风格拉回 Ant Design。

- `AntdButton`
- `AntdInput`
- `AntdCard`
- `AntdTag`
- `AntdAlert`
- `AntdDivider`
- `AntdEmpty`
- `AntdSpin`
- `AntdSpace`

### 第二层：表单与选择组件

用于登录、初始化、主机编辑、系统设置、用户管理。

- `AntdFormItem`
- `AntdPasswordInput`
- `AntdTextArea`
- `AntdSelect`
- `AntdCheckbox`
- `AntdSwitch`
- `AntdRadioGroup`
- `AntdDateInput`

### 第三层：布局与反馈组件

用于 Dashboard、弹窗、抽屉、工具栏。

- `AntdToolbar`
- `AntdModal`
- `AntdDrawer`
- `AntdTabs`
- `AntdDropdown`
- `AntdTooltip`

### 第四层：数据展示组件

用于主机管理、用户管理、连接历史、监控列表、录像列表。

- `AntdTable`
- `AntdTableColumn`
- `AntdPagination`
- `AntdActionMenu`
- `AntdStatusBadge`

表格可以先自研轻量版，支持固定表头、横向滚动、列宽、选择列、操作列、空状态、加载状态。后续若需要复杂列冻结和虚拟滚动，再评估 `data_table_2` 或 `pluto_grid`。

## 组件 API 草案

### AntdButton

```dart
AntdButton(
  type: AntdButtonType.primary,
  size: AntdSize.small,
  icon: Icons.add,
  loading: false,
  danger: false,
  block: false,
  onPressed: () {},
  child: const Text('添加主机'),
)
```

支持类型：

- `primary`
- `default`
- `dashed`
- `text`
- `link`

验收重点：

- `small` 高度为 `24`
- 默认高度为 `32`
- 主按钮背景 `#1890ff`
- 禁用态、hover/pressed 态不能出现 Material 默认紫色或大圆角

### AntdInput

```dart
AntdInput(
  controller: controller,
  placeholder: '请输入用户名',
  prefixIcon: Icons.person_outline,
  obscureText: false,
  onSubmitted: (_) {},
)
```

验收重点：

- 高度、边框、focus 边框、placeholder 颜色贴近 `a-input`
- 支持 prefix/suffix
- 支持错误态

### AntdFormItem

```dart
AntdFormItem(
  label: '用户名',
  required: true,
  help: errorText,
  child: AntdInput(...),
)
```

验收重点：

- label 在上方
- label 与控件间距接近 Web
- required 星号与错误文案样式统一

### AntdCard

```dart
AntdCard(
  title: const Text('主机'),
  extra: toolbar,
  bordered: false,
  child: content,
)
```

验收重点：

- header 高度约 `40`
- body padding 默认 `12`
- `bordered: false` 时无外边框
- 圆角 `8`

### AntdTable

```dart
AntdTable<Host>(
  rowKey: (host) => host.id.toString(),
  loading: loading,
  data: hosts,
  selectedKeys: selectedKeys,
  onSelectionChanged: onSelectionChanged,
  columns: [
    AntdTableColumn(title: '', width: 36, cell: dragHandle),
    AntdTableColumn(title: '名称', width: 180, cell: hostNameCell),
    AntdTableColumn(title: '状态', width: 100, cell: statusCell),
    AntdTableColumn(title: '操作', width: 160, cell: actionCell),
  ],
)
```

第一版能力：

- 表头
- 固定列宽
- 横向滚动
- 行选择
- loading
- empty
- row actions
- mobile 宽度下横向滚动

暂缓能力：

- 列冻结
- 虚拟滚动
- 拖拽排序
- 单元格编辑

## 迁移策略

### 阶段 1：建立基础组件

交付物：

- `antd_theme.dart`
- `widgets/antd/index.dart`
- `AntdButton`
- `AntdInput`
- `AntdFormItem`
- `AntdCard`
- `AntdTag`
- `AntdAlert`
- `AntdEmpty`
- `AntdSpin`
- `AntdSpace`

优先替换页面：

- `login_screen.dart`
- `setup_screen.dart`
- `forgot_password_screen.dart`
- `reset_password_screen.dart`
- `auth_scaffold.dart`

验收标准：

- 登录/初始化/忘记密码/重置密码页面和 Web 的卡片尺寸、表单密度、按钮高度基本一致。
- 页面中不再直接使用 `TextField`、`ElevatedButton`、`OutlinedButton` 来实现 Ant Design 表单。

### 阶段 2：终端页与 Dashboard 壳

交付物：

- `AntdToolbar`
- `AntdTabs`
- `AntdDropdown`
- `AntdModal`
- `AntdSwitch`

优先替换页面：

- `home_screen.dart`
- `terminal_tabs_screen.dart`
- `terminal_session_screen.dart`
- `host_edit_dialog.dart`

验收标准：

- 终端页工具栏与 Web 的选择主机、新建、快速连接、录制开关位置一致。
- tab 高度、关闭按钮、录制红点、空状态与 Web 靠近。
- 主机编辑弹窗结构和 Web 字段顺序一致。

### 阶段 3：主机管理表格

交付物：

- `AntdTable`
- `AntdPagination`
- `AntdActionMenu`
- `AntdStatusBadge`

优先替换页面：

- `host_management_screen.dart`

验收标准：

- 从卡片列表改为表格结构。
- 支持搜索、快速过滤、显示/隐藏删除、批量操作入口。
- 表格列对齐 Web：拖拽、名称、状态、监控、描述、类型、到期日期、计费周期、剩余价值、操作。

### 阶段 4：监控页

交付物：

- `AntdSegmented`
- `AntdProgress`
- `AntdPopover`
- `AntdMetricCard`

优先替换页面：

- `monitor_tab.dart`

验收标准：

- 支持卡片/列表模式切换。
- 卡片操作按钮对齐 Web：网络详情、连接、历史、设置。
- 支持状态历史弹窗、流量重置日志、模板入口、批量更新入口。

### 阶段 5：SFTP 与复杂业务组件

交付物：

- `AntdUploadProgressDock`
- `AntdConflictModal`
- `AntdFileList`
- `AntdSplitPane`

优先替换页面：

- `file_transfer_screen.dart`

验收标准：

- 对齐 Web 的 SFTP 浏览器、上传队列、冲突弹窗、进度 Dock、文件编辑入口。

## 页面替换规则

为了避免继续出现“一页一个风格”，后续页面迁移遵循这些规则：

- 新增页面不得直接使用 `ElevatedButton`、`OutlinedButton`、`TextButton` 表达 Ant Design 按钮，必须通过 `AntdButton`。
- 表单输入不得直接使用裸 `TextField`，必须通过 `AntdInput`、`AntdPasswordInput`、`AntdTextArea`。
- 页面级卡片不得直接使用 `Card`，必须通过 `AntdCard`。
- 状态标签不得手写 `Container + Text`，必须通过 `AntdTag` 或 `AntdStatusBadge`。
- 页面工具栏必须使用 `AntdToolbar`，保证间距和移动端折叠一致。
- 表格类页面必须优先使用 `AntdTable`，除非有明确技术原因。

## 验收方式

每个阶段完成后至少检查：

- `flutter build web`
- 桌面宽度 `1440 x 900`
- 平板宽度 `768 x 1024`
- 手机宽度 `390 x 844`
- 浅色模式
- 暗色模式
- 空数据
- 有数据
- loading
- error

视觉验收维度：

- 元素是否在同一位置
- 文案是否一致
- 按钮高度是否一致
- 表单间距是否一致
- 表格列是否一致
- 弹窗宽度是否一致
- 暗色模式颜色是否一致
- 移动端是否没有 `BOTTOM` 溢出

## 风险与取舍

### 风险 1：自研组件增加工作量

这是必要成本。直接用 Material 组件继续做页面，会持续偏离 Web；自研组件能把成本前置，后续页面迁移会更稳定。

### 风险 2：AntdTable 复杂度高

第一版不要追求完整表格能力。先做能复刻当前页面的轻量表格，再根据主机管理、用户管理、连接历史逐步补能力。

### 风险 3：Flutter Web 与移动端诉求冲突

项目目标是复刻 Web，所以桌面 Web 布局优先。移动端只做响应式适配，不为了移动端体验重新设计页面结构。

### 风险 4：服务器地址字段导致页面不完全一致

Flutter 独立运行需要服务器地址。解决方式是把服务器地址作为可折叠的连接配置，或在部署模式下从环境/构建参数注入默认 API 地址。短期保留字段，长期可做部署模式区分。

## 推荐执行顺序

1. 新建 `widgets/antd` 目录和 `index.dart`。
2. 扩展 `AntdTokens`，补齐颜色、字体、间距、控件高度。
3. 实现 `AntdButton`、`AntdInput`、`AntdFormItem`、`AntdCard`。
4. 替换登录/初始化/忘记密码/重置密码页面。
5. 实现 `AntdTag`、`AntdAlert`、`AntdEmpty`、`AntdSpin`。
6. 替换终端页工具栏和空状态。
7. 实现 `AntdModal`、`AntdSelect`、`AntdRadioGroup`、`AntdSwitch`。
8. 替换主机编辑弹窗。
9. 实现第一版 `AntdTable`。
10. 迁移主机管理页面到表格结构。

## 完成定义

当下面条件满足时，认为 AntdFlutter 基础组件第一阶段完成：

- `widgets/antd/index.dart` 能覆盖登录、初始化、终端工具栏、主机编辑弹窗的基础控件需求。
- 已迁移页面不再暴露明显 Material 风格控件。
- `flutter build web` 通过。
- `WEB_PARITY_AUDIT.md` 中公共流程与终端基础区域可以标记为“基本对齐”。
