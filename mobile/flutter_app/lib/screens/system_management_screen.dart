import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

class SystemManagementScreen extends StatefulWidget {
  const SystemManagementScreen({super.key});

  @override
  State<SystemManagementScreen> createState() => _SystemManagementScreenState();
}

class _SystemManagementScreenState extends State<SystemManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  // Settings inputs
  final _sshTimeoutController = TextEditingController(text: '30');
  final _idleTimeoutController = TextEditingController(text: '3600');
  final _maxConnController = TextEditingController(text: '10');
  final _loginRateController = TextEditingController(text: '5');
  final _tokenExpController = TextEditingController(text: '24');

  // SMTP inputs
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _smtpFromController = TextEditingController();
  final _smtpToController = TextEditingController();

  // Telegram inputs
  final _tgTokenController = TextEditingController();
  final _tgChatIdController = TextEditingController();

  // DB stats
  Map<String, dynamic> _dbStats = {};

  // Templates
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();

    // Load Settings
    final settings = await state.getSystemSettings();
    if (settings != null) {
      _sshTimeoutController.text = settings['ssh_timeout']?.toString() ?? '30';
      _idleTimeoutController.text =
          settings['idle_timeout']?.toString() ?? '3600';
      _maxConnController.text =
          settings['max_connections_per_user']?.toString() ?? '10';
      _loginRateController.text =
          settings['login_rate_limit']?.toString() ?? '5';
      _tokenExpController.text =
          settings['token_expiration']?.toString() ?? '24';

      _smtpServerController.text = settings['smtp_server'] ?? '';
      _smtpPortController.text = settings['smtp_port']?.toString() ?? '465';
      _smtpUserController.text = settings['smtp_user'] ?? '';
      _smtpPasswordController.text = settings['smtp_password'] ?? '';
      _smtpFromController.text = settings['smtp_from'] ?? '';
      _smtpToController.text = settings['smtp_to'] ?? '';

      _tgTokenController.text = settings['telegram_token'] ?? '';
      _tgChatIdController.text = settings['telegram_chat_id'] ?? '';
    }

    // Load DB Stats
    final stats = await state.getDbStats();
    if (stats != null) {
      _dbStats = stats;
    }

    // Load Latency Templates
    final templatesList = await state.getNetworkTemplates();
    _templates = templatesList;

    setState(() => _isLoading = false);
  }

  Map<String, dynamic> _collectSettings() {
    return {
      'ssh_timeout': int.tryParse(_sshTimeoutController.text) ?? 30,
      'idle_timeout': int.tryParse(_idleTimeoutController.text) ?? 3600,
      'max_connections_per_user': int.tryParse(_maxConnController.text) ?? 10,
      'login_rate_limit': int.tryParse(_loginRateController.text) ?? 5,
      'token_expiration': int.tryParse(_tokenExpController.text) ?? 24,
      'smtp_server': _smtpServerController.text.trim(),
      'smtp_port': int.tryParse(_smtpPortController.text) ?? 465,
      'smtp_user': _smtpUserController.text.trim(),
      'smtp_password': _smtpPasswordController.text.trim(),
      'smtp_from': _smtpFromController.text.trim(),
      'smtp_to': _smtpToController.text.trim(),
      'telegram_token': _tgTokenController.text.trim(),
      'telegram_chat_id': _tgChatIdController.text.trim(),
    };
  }

  void _saveSettings() async {
    final state = context.read<AppState>();
    final success = await state.saveSystemSettings(_collectSettings());
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(Translation.getText(state.locale, 'common.saveSuccess'))),
      );
    }
  }

  void _testEmail() async {
    final state = context.read<AppState>();
    final success = await state.testEmailNotification(_collectSettings());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(success ? 'Test email dispatched!' : 'Dispatch failed.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _testTelegram() async {
    final state = context.read<AppState>();
    final success = await state.testTelegramNotification(_collectSettings());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Test telegram msg sent!' : 'Send failed.'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _triggerBackup() {
    final ctrl = TextEditingController();
    final state = context.read<AppState>();
    showDialog(
        context: context,
        builder: (dialogContext) => AntdModal(
              title:
                  Text(Translation.getText(state.locale, 'system.backupTitle')),
              width: 420,
              okText: Translation.getText(state.locale, 'common.confirm'),
              cancelText: Translation.getText(state.locale, 'common.cancel'),
              onOk: () async {
                final res = await state.backupDatabase(ctrl.text);
                if (res != null && mounted && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _showBackupResult(res);
                }
              },
              child: AntdPasswordInput(
                  controller: ctrl,
                  placeholder:
                      '\u5907\u4efd\u5bc6\u7801\uff08\u53ef\u9009\uff09'),
            ));
  }

  void _showBackupResult(Map<String, dynamic> res) {
    showDialog(
        context: context,
        builder: (dialogContext) => AntdModal(
              title: const Text('\u5907\u4efd\u6210\u529f'),
              width: 400,
              okText: 'OK',
              cancelText: '',
              onOk: () => Navigator.of(dialogContext).pop(),
              child: Text(
                  '\u6587\u4ef6\u8def\u5f84: ${res['filepath']}\n\u5927\u5c0f: ${res['size'] ?? ''} bytes'),
            ));
  }

  void _pruneData() {
    final st = context.read<AppState>();
    showDialog(
        context: context,
        builder: (dialogContext) => AntdModal(
              title: Text(
                  Translation.getText(st.locale, 'system.pruneConfirmTitle')),
              width: 420,
              danger: true,
              okText: Translation.getText(st.locale, 'common.confirm'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                final res = await st.pruneMonitorData();
                if (res != null && mounted && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '\u5df2\u6e05\u7406\uff01\u5220\u9664 ${res['deleted_count'] ?? 0} \u884c\u3002')));
                  _loadAllData();
                }
              },
              child: Text(
                  Translation.getText(st.locale, 'system.pruneConfirmContent')),
            ));
  }

  void _showAddEditTemplateDialog([Map<String, dynamic>? tmpl]) {
    final isEdit = tmpl != null;
    final state = context.read<AppState>();
    final nameC = TextEditingController(text: isEdit ? tmpl['name'] : '');
    final typeC = TextEditingController(text: isEdit ? tmpl['type'] : 'ping');
    final intervalC = TextEditingController(
        text: isEdit ? tmpl['interval']?.toString() : '60');
    final targetC =
        TextEditingController(text: isEdit ? tmpl['target'] : '8.8.8.8');
    final colorC = TextEditingController(
        text: isEdit ? tmpl['indicator_color'] : '#64D2FF');

    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (dialogContext, setDlg) => AntdModal(
                  title: Text(isEdit
                      ? '\u7f16\u8f91\u6a21\u677f'
                      : '\u65b0\u5efa\u6a21\u677f'),
                  width: 480,
                  okText: Translation.getText(state.locale, 'common.confirm'),
                  cancelText:
                      Translation.getText(state.locale, 'common.cancel'),
                  onOk: () async {
                    if (nameC.text.trim().isEmpty ||
                        targetC.text.trim().isEmpty) return;
                    final data = {
                      'name': nameC.text,
                      'type': typeC.text,
                      'interval': int.tryParse(intervalC.text) ?? 60,
                      'target': targetC.text,
                      'indicator_color': colorC.text
                    };
                    final ok = isEdit
                        ? await state.updateNetworkTemplate(
                            tmpl['id'] as int, data)
                        : await state.createNetworkTemplate(data);
                    if (ok && mounted && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                      _loadAllData();
                    }
                  },
                  child: Column(children: [
                    AntdFormItem(
                        label: '\u6a21\u677f\u540d\u79f0',
                        child: AntdInput(controller: nameC)),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u7c7b\u578b',
                        child: AntdSelect<String>(
                            value: typeC.text,
                            options: const [
                              AntdSelectOption(value: 'ping', label: 'Ping'),
                              AntdSelectOption(
                                  value: 'tcping', label: 'TCPing'),
                            ],
                            onChanged: (v) {
                              if (v != null) setDlg(() => typeC.text = v);
                            })),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u76ee\u6807 (IP/\u4e3b\u673a)',
                        child: AntdInput(controller: targetC)),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u9891\u7387 (\u79d2)',
                        child: AntdInput(
                            controller: intervalC,
                            keyboardType: TextInputType.number)),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u56fe\u8868\u989c\u8272',
                        child: AntdInput(controller: colorC)),
                  ]),
                )));
  }

  void _deployTemplate(Map<String, dynamic> tmpl) {
    final state = context.read<AppState>();
    final selected = <int>[];
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (dialogContext, setDlg) => AntdModal(
                  title: Text('\u90e8\u7f72: ${tmpl['name']}'),
                  width: 500,
                  bodyMaxHeight: 300,
                  okText: '\u90e8\u7f72',
                  cancelText:
                      Translation.getText(state.locale, 'common.cancel'),
                  onOk: selected.isEmpty
                      ? null
                      : () async {
                          final ok = await state.batchApplyNetworkTemplate(
                              tmpl['id'] as int, selected);
                          if (ok && mounted && dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '\u5ef6\u8fdf\u6a21\u677f\u5df2\u90e8\u7f72\uff01'),
                                    backgroundColor: Colors.green));
                          }
                        },
                  child: state.hosts.isEmpty
                      ? const AntdEmpty(
                          description: '\u6682\u65e0\u53ef\u7528\u4e3b\u673a')
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: state.hosts.length,
                          itemBuilder: (_, i) {
                            final h = state.hosts[i];
                            final sel = selected.contains(h.id);
                            return CheckboxListTile(
                                title: Text(h.name),
                                subtitle: Text(h.host),
                                value: sel,
                                onChanged: (v) => setDlg(() {
                                      if (v == true)
                                        selected.add(h.id);
                                      else
                                        selected.remove(h.id);
                                    }));
                          }),
                )));
  }

  void _deleteTemplate(Map<String, dynamic> tmpl) {
    final st = context.read<AppState>();
    showDialog(
        context: context,
        builder: (dialogContext) => AntdModal(
              title:
                  Text(Translation.getText(st.locale, 'common.confirmDelete')),
              width: 400,
              danger: true,
              okText: Translation.getText(st.locale, 'common.confirm'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                final ok = await st.deleteNetworkTemplate(tmpl['id'] as int);
                if (ok && mounted && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  _loadAllData();
                }
              },
              child: Text(
                  '\u786e\u5b9a\u8981\u5220\u9664 ${tmpl['name']} \u5417\uff1f'),
            ));
  }

  // UI tabs
  Widget _buildParamTab(AppState state) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(state.locale, 'system.settingsTitle'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1890FF)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sshTimeoutController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.sshTimeout')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _idleTimeoutController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.idleTimeout')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxConnController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.maxConnectionsPerUser')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _loginRateController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.loginRateLimit')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenExpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Token Expiration (Hours)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AntdButton(
              type: AntdButtonType.primary,
              block: true,
              onPressed: _saveSettings,
              child: Text(Translation.getText(state.locale, 'common.save'))),
        ],
      ),
    );
  }

  Widget _buildChannelTab(AppState state) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SMTP Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.email, color: Color(0xFF1890FF)),
                      SizedBox(width: 8),
                      Text('SMTP Alerts Settings',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpServerController,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.smtpServer')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpPortController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.smtpPort')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpUserController,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.smtpUser')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.smtpPassword')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpFromController,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.smtpFrom')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpToController,
                    decoration: InputDecoration(
                        labelText:
                            Translation.getText(state.locale, 'system.smtpTo')),
                  ),
                  const SizedBox(height: 12),
                  AntdButton(
                      onPressed: _testEmail,
                      child: Text(Translation.getText(
                          state.locale, 'system.testEmail'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Telegram Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.send, color: Color(0xFF2ED573)),
                      SizedBox(width: 8),
                      Text('Telegram Alerts Settings',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tgTokenController,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.telegramToken')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tgChatIdController,
                    decoration: InputDecoration(
                        labelText: Translation.getText(
                            state.locale, 'system.telegramChatId')),
                  ),
                  const SizedBox(height: 12),
                  AntdButton(
                      onPressed: _testTelegram,
                      child: Text(Translation.getText(
                          state.locale, 'system.testTelegram'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AntdButton(
              type: AntdButtonType.primary,
              block: true,
              onPressed: _saveSettings,
              child: Text(Translation.getText(state.locale, 'common.save'))),
        ],
      ),
    );
  }

  Widget _buildDbTab(AppState state) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Database Backup Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(state.locale, 'system.backupTitle'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1890FF)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translation.getText(state.locale, 'system.backupDesc'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  AntdButton(
                      type: AntdButtonType.primary,
                      icon: Icons.backup,
                      onPressed: _triggerBackup,
                      child: Text(Translation.getText(
                          state.locale, 'system.startBackup'))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Database Maintenance Card
          Card(
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(
                        state.locale, 'system.dbMaintenanceTitle'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF2ED573)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translation.getText(
                        state.locale, 'system.dbMaintenanceDesc'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Text('Database rows:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.8))),
                  const SizedBox(height: 8),
                  if (_dbStats.isNotEmpty)
                    Table(
                      border: TableBorder.all(color: Colors.white10),
                      children: _dbStats.entries.map((entry) {
                        return TableRow(
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(entry.key,
                                    style: const TextStyle(fontSize: 12))),
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(entry.value.toString(),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1890FF)))),
                          ],
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  AntdButton(
                      type: AntdButtonType.primary,
                      icon: Icons.cleaning_services,
                      danger: true,
                      onPressed: _pruneData,
                      child: Text(Translation.getText(
                          state.locale, 'system.pruneMonitorData'))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkTab(AppState state) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditTemplateDialog(),
        backgroundColor: const Color(0xFF1890FF),
        mini: true,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _templates.isEmpty
          ? const Center(
              child: Text('No templates configured',
                  style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _templates.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (ctx, idx) {
                final tmpl = _templates[idx];
                final colorHex = tmpl['indicator_color'] ?? '#64D2FF';
                Color chipColor = const Color(0xFF1890FF);
                try {
                  chipColor = Color(
                      int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));
                } catch (_) {}

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: chipColor.withOpacity(0.2),
                      child: Icon(Icons.speed, color: chipColor),
                    ),
                    title: Text(tmpl['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${tmpl['type']?.toUpperCase() ?? 'PING'} • ${tmpl['target']} • Freq: ${tmpl['interval']}s'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      AntdButton(
                          type: AntdButtonType.text,
                          icon: Icons.arrow_circle_right_outlined,
                          onPressed: () => _deployTemplate(tmpl)),
                      AntdButton(
                          type: AntdButtonType.text,
                          icon: Icons.edit,
                          onPressed: () => _showAddEditTemplateDialog(tmpl)),
                      AntdButton(
                          type: AntdButtonType.text,
                          icon: Icons.delete,
                          danger: true,
                          onPressed: () => _deleteTemplate(tmpl)),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Column(children: [
      AntdTabs(
          items: const [
            AntdTabsItem(key: '0', label: Text('\u8bbe\u7f6e')),
            AntdTabsItem(key: '1', label: Text('\u901a\u77e5\u6e20\u9053')),
            AntdTabsItem(
                key: '2', label: Text('\u6570\u636e\u5e93\u7ef4\u62a4')),
            AntdTabsItem(key: '3', label: Text('\u5ef6\u8fdf\u6a21\u677f')),
          ],
          activeKey: _tabController.index.toString(),
          onChange: (k) => _tabController.animateTo(int.parse(k))),
      Expanded(
          child: _isLoading
              ? const AntdSpin()
              : TabBarView(controller: _tabController, children: [
                  _buildParamTab(state),
                  _buildChannelTab(state),
                  _buildDbTab(state),
                  _buildNetworkTab(state),
                ])),
    ]);
  }
}
