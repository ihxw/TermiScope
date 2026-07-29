import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';

class HostEditDialog extends StatefulWidget {
  final Map<String, dynamic>? host;
  final Map<String, dynamic>? initialValues;
  final String? title;
  final String? okText;

  const HostEditDialog({
    super.key,
    this.host,
    this.initialValues,
    this.title,
    this.okText,
  });

  @override
  State<HostEditDialog> createState() => _HostEditDialogState();
}

class _HostEditDialogState extends State<HostEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _groupController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _expirationController;
  late final TextEditingController _billingAmountController;
  String _hostType = 'control_monitor';
  String _authType = 'password';
  String _remoteShell = 'default';
  String _osType = 'linux';
  String _flag = '';
  String _billingPeriod = '';
  String _currency = 'CNY';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final host = widget.host ?? widget.initialValues;
    _nameController = TextEditingController(text: host?['name'] ?? '');
    _hostController = TextEditingController(text: host?['host'] ?? '');
    _portController =
        TextEditingController(text: host?['port']?.toString() ?? '22');
    _usernameController = TextEditingController(text: host?['username'] ?? '');
    _passwordController = TextEditingController();
    _privateKeyController = TextEditingController();
    _groupController = TextEditingController(text: host?['group_name'] ?? '');
    _descriptionController =
        TextEditingController(text: host?['description'] ?? '');
    _expirationController =
        TextEditingController(text: host?['expiration_date'] ?? '');
    _billingAmountController =
        TextEditingController(text: host?['billing_amount']?.toString() ?? '');
    _hostType = host?['host_type'] ?? 'control_monitor';
    if (_hostType == 'ssh') _hostType = 'control_monitor';
    _authType = host?['auth_type'] ?? 'password';
    _remoteShell = host?['remote_shell'] ?? 'default';
    _osType = host?['os_type'] ?? 'linux';
    _flag = host?['flag'] ?? '';
    _billingPeriod = host?['billing_period'] ?? '';
    _currency = host?['currency'] ?? 'CNY';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _groupController.dispose();
    _descriptionController.dispose();
    _expirationController.dispose();
    _billingAmountController.dispose();
    super.dispose();
  }

  // ---------- 选择项列表 ----------
  static const _typeOptions = [
    AntdSelectOption(value: 'control_monitor', label: '控制+监控'),
    AntdSelectOption(value: 'monitor_only', label: '仅监控'),
  ];

  static const _osOptions = [
    AntdSelectOption(value: 'linux', label: 'Linux'),
    AntdSelectOption(value: 'windows', label: 'Windows'),
  ];

  static const _shellOptions = [
    AntdSelectOption(value: 'default', label: '默认'),
    AntdSelectOption(value: 'powershell', label: 'PowerShell'),
    AntdSelectOption(value: 'pwsh', label: 'PowerShell Core'),
    AntdSelectOption(value: 'cmd', label: 'CMD'),
    AntdSelectOption(value: 'bash', label: 'Bash'),
  ];

  static const _billingOptions = [
    AntdSelectOption(value: '', label: '不设置'),
    AntdSelectOption(value: 'monthly', label: '月付'),
    AntdSelectOption(value: 'quarterly', label: '季付'),
    AntdSelectOption(value: 'semiannually', label: '半年付'),
    AntdSelectOption(value: 'annually', label: '年付'),
    AntdSelectOption(value: 'biennial', label: '2年付'),
    AntdSelectOption(value: 'triennial', label: '3年付'),
    AntdSelectOption(value: '4year', label: '4年付'),
    AntdSelectOption(value: '5year', label: '5年付'),
    AntdSelectOption(value: '6year', label: '6年付'),
    AntdSelectOption(value: '7year', label: '7年付'),
    AntdSelectOption(value: '8year', label: '8年付'),
    AntdSelectOption(value: '9year', label: '9年付'),
    AntdSelectOption(value: '10year', label: '10年付'),
  ];

  static const _currencyOptions = [
    AntdSelectOption(value: 'CNY', label: '¥ CNY'),
    AntdSelectOption(value: 'USD', label: '\$ USD'),
    AntdSelectOption(value: 'EUR', label: '€ EUR'),
    AntdSelectOption(value: 'GBP', label: '£ GBP'),
    AntdSelectOption(value: 'JPY', label: '¥ JPY'),
  ];

  static const _flagOptions = [
    _FlagOption('', null),
    _FlagOption('red', Color(0xFFFF4D4F)),
    _FlagOption('orange', Color(0xFFFF7A45)),
    _FlagOption('yellow', Color(0xFFFAAD14)),
    _FlagOption('green', Color(0xFF52C41A)),
    _FlagOption('blue', Color(0xFF1890FF)),
    _FlagOption('purple', Color(0xFF722ED1)),
  ];

  // ---------- 保存 ----------
  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final hostData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'host': _hostController.text.trim(),
      'port': int.tryParse(_portController.text.trim()) ?? 22,
      'username': _usernameController.text.trim(),
      'monitor_enabled': widget.host?['monitor_enabled'] ?? true,
      'host_type': _hostType,
      'auth_type': _authType,
      'remote_shell': _remoteShell,
      'os_type': _osType,
      'group_name': _groupController.text.trim(),
      'description': _descriptionController.text.trim(),
      'flag': _flag,
      'expiration_date': _expirationController.text.trim().isEmpty
          ? null
          : _expirationController.text.trim(),
      'billing_period': _billingPeriod.isEmpty ? null : _billingPeriod,
      'billing_amount':
          double.tryParse(_billingAmountController.text.trim()) ?? 0,
      'currency': _currency,
    };

    if (_passwordController.text.isNotEmpty) {
      hostData['password'] = _passwordController.text;
    }
    if (_privateKeyController.text.isNotEmpty) {
      hostData['private_key'] = _privateKeyController.text;
    }

    setState(() => _saving = true);
    final appState = context.read<AppState>();

    final success = widget.host == null
        ? await appState.addHost(hostData)
        : await appState.updateHost(widget.host!['id'].toString(), hostData);

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.host == null ? '主机添加成功' : '主机更新成功')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.host == null ? '添加失败' : '更新失败')),
      );
    }
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return AntdModal(
      title: Text(widget.title ?? (widget.host == null ? '添加主机' : '编辑主机')),
      width: 560,
      bodyMaxHeight: 600,
      showFooter: true,
      okText: widget.okText ?? (widget.host == null ? '添加' : '保存'),
      cancelText: '取消',
      confirmLoading: _saving,
      onOk: _save,
      onCancel: () => Navigator.pop(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 主机类型
            AntdFormItem(
              label: '类型',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AntdSelect(
                    value: _hostType,
                    options: _typeOptions,
                    onChanged: (v) {
                      if (v != null) setState(() => _hostType = v);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _hostType == 'control_monitor'
                        ? 'SSH 控制 + 监控代理'
                        : '仅进行性能监控，不启用 SSH 控制台',
                    style: TextStyle(
                      fontSize: AntdTokens.fontSizeSM,
                      color: AntdTokens.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 名称
            AntdFormItem(
              label: '名称',
              required: true,
              child: AntdInput(
                controller: _nameController,
                placeholder: '请输入名称',
                prefixIcon: Icons.computer,
                onChanged: (_) => _formKey.currentState?.validate(),
              ),
            ),
            const SizedBox(height: 12),

            if (_hostType == 'control_monitor') ...[
              // 主机地址
              AntdFormItem(
                label: '主机地址',
                required: true,
                child: AntdInput(
                  controller: _hostController,
                  placeholder: '请输入主机地址',
                  prefixIcon: Icons.dns,
                ),
              ),
              const SizedBox(height: 12),

              // 端口
              AntdFormItem(
                label: '端口',
                child: AntdInput(
                  controller: _portController,
                  placeholder: '22',
                  prefixIcon: Icons.input,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(height: 12),

              // 用户名
              AntdFormItem(
                label: '用户名',
                child: AntdInput(
                  controller: _usernameController,
                  placeholder: 'SSH 用户名',
                  prefixIcon: Icons.person,
                ),
              ),
              const SizedBox(height: 12),

              // 认证方式
              AntdFormItem(
                label: '认证方式',
                child: AntdRadioGroup<String>(
                  value: _authType,
                  options: const [
                    AntdRadioOption(value: 'password', label: '密码认证'),
                    AntdRadioOption(value: 'key', label: '密钥认证'),
                  ],
                  onChanged: (v) => setState(() => _authType = v),
                ),
              ),
              const SizedBox(height: 12),

              // 密码 / 私钥
              if (_authType == 'password')
                AntdFormItem(
                  label: '密码',
                  help: widget.host != null ? '留空以保持当前密码' : null,
                  child: AntdPasswordInput(
                    controller: _passwordController,
                    placeholder: widget.host != null ? '留空以保持当前密码' : '请输入密码',
                    prefixIcon: Icons.lock,
                  ),
                )
              else
                AntdFormItem(
                  label: '私钥',
                  help: widget.host != null ? '留空以保持当前密钥' : null,
                  child: AntdTextArea(
                    controller: _privateKeyController,
                    placeholder: widget.host != null ? '留空以保持当前密钥' : '粘贴私钥内容',
                    minLines: 3,
                    maxLines: 6,
                  ),
                ),
              const SizedBox(height: 12),

              // 远程 Shell
              AntdFormItem(
                label: '远程 Shell',
                child: AntdSelect(
                  value: _remoteShell,
                  options: _shellOptions,
                  onChanged: (v) {
                    if (v != null) setState(() => _remoteShell = v);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 系统类型
            AntdFormItem(
              label: '系统类型',
              child: AntdSelect(
                value: _osType,
                options: _osOptions,
                onChanged: (v) {
                  if (v != null) setState(() => _osType = v);
                },
              ),
            ),
            const SizedBox(height: 12),

            // 分组
            AntdFormItem(
              label: '分组',
              child: AntdInput(
                controller: _groupController,
                placeholder: '生产环境',
                prefixIcon: Icons.folder,
              ),
            ),
            const SizedBox(height: 12),

            // 描述
            AntdFormItem(
              label: '描述',
              child: AntdTextArea(
                controller: _descriptionController,
                placeholder: '描述信息',
                minLines: 2,
                maxLines: 4,
              ),
            ),
            const SizedBox(height: 12),

            // 标记
            AntdFormItem(
              label: '标记',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _flagOptions.map((opt) {
                  final selected = _flag == opt.value;
                  return GestureDetector(
                    onTap: () => setState(() => _flag = opt.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: EdgeInsets.symmetric(
                        horizontal: opt.value.isEmpty ? 10 : 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AntdTokens.primary.withAlpha(30)
                            : AntdTokens.containerSecondaryColor(context),
                        border: Border.all(
                          color: selected
                              ? AntdTokens.primary
                              : AntdTokens.borderColor(context),
                        ),
                        borderRadius: BorderRadius.circular(AntdTokens.radius),
                      ),
                      child: opt.value.isEmpty
                          ? Text(
                              '无',
                              style: TextStyle(
                                fontSize: AntdTokens.fontSizeSM,
                                color: selected
                                    ? AntdTokens.primary
                                    : AntdTokens.textColor(context),
                              ),
                            )
                          : Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: opt.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // 财务管理分割线
            const SizedBox(height: 8),
            const AntdDivider(text: '财务管理'),
            const SizedBox(height: 8),

            // 到期日期
            AntdFormItem(
              label: '到期日期',
              child: AntdInput(
                controller: _expirationController,
                placeholder: 'YYYY-MM-DD',
                prefixIcon: Icons.event_available,
              ),
            ),
            const SizedBox(height: 12),

            // 计费周期
            AntdFormItem(
              label: '计费周期',
              child: AntdSelect(
                value: _billingPeriod,
                options: _billingOptions,
                onChanged: (v) {
                  if (v != null) setState(() => _billingPeriod = v);
                },
              ),
            ),
            const SizedBox(height: 12),

            // 币种 + 金额
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 2,
                  child: AntdFormItem(
                    label: '币种',
                    child: AntdSelect(
                      value: _currency,
                      options: _currencyOptions,
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: AntdFormItem(
                    label: '费用金额',
                    child: AntdInput(
                      controller: _billingAmountController,
                      placeholder: '0.00',
                      prefixIcon: Icons.payments,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagOption {
  final String value;
  final Color? color;
  const _FlagOption(this.value, this.color);
}
