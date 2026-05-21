import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';

class SystemManagementScreen extends StatefulWidget {
  const SystemManagementScreen({super.key});

  @override
  State<SystemManagementScreen> createState() => _SystemManagementScreenState();
}

class _SystemManagementScreenState extends State<SystemManagementScreen> with SingleTickerProviderStateMixin {
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
      _idleTimeoutController.text = settings['idle_timeout']?.toString() ?? '3600';
      _maxConnController.text = settings['max_connections_per_user']?.toString() ?? '10';
      _loginRateController.text = settings['login_rate_limit']?.toString() ?? '5';
      _tokenExpController.text = settings['token_expiration']?.toString() ?? '24';

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
        SnackBar(content: Text(Translation.getText(state.locale, 'common.saveSuccess'))),
      );
    }
  }

  void _testEmail() async {
    final state = context.read<AppState>();
    final success = await state.testEmailNotification(_collectSettings());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Test email dispatched!' : 'Dispatch failed.'),
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
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'system.backupTitle')),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Backup password (Optional)'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await state.backupDatabase(controller.text);
                if (res != null && mounted) {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Backup Success'),
                      content: Text('File Path: ${res['filepath']}\nSize: ${res['size'] ?? ''} bytes'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('OK'),
                        )
                      ],
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _pruneData() {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'system.pruneConfirmTitle')),
          content: Text(Translation.getText(state.locale, 'system.pruneConfirmContent')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await state.pruneMonitorData();
                if (res != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pruned success! Removed ${res['deleted_count'] ?? 0} rows.')),
                  );
                  _loadAllData();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _showAddEditTemplateDialog([Map<String, dynamic>? tmpl]) {
    final isEdit = tmpl != null;
    final nameController = TextEditingController(text: isEdit ? tmpl['name'] : '');
    final typeController = TextEditingController(text: isEdit ? tmpl['type'] : 'ping');
    final intervalController = TextEditingController(text: isEdit ? tmpl['interval']?.toString() : '60');
    final targetController = TextEditingController(text: isEdit ? tmpl['target'] : '8.8.8.8');
    final colorController = TextEditingController(text: isEdit ? tmpl['indicator_color'] : '#64D2FF');

    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Template' : 'New Template'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Template Name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: typeController.text,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'ping', child: Text('Ping')),
                        DropdownMenuItem(value: 'tcping', child: Text('TCPing')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => typeController.text = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: targetController,
                      decoration: const InputDecoration(labelText: 'Target (IP / Host)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: intervalController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Frequency (Seconds)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(labelText: 'Chart line hex color'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(Translation.getText(state.locale, 'common.cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final data = {
                      'name': nameController.text,
                      'type': typeController.text,
                      'interval': int.tryParse(intervalController.text) ?? 60,
                      'target': targetController.text,
                      'indicator_color': colorController.text,
                    };
                    bool success;
                    if (isEdit) {
                      success = await state.updateNetworkTemplate(tmpl['id'] as int, data);
                    } else {
                      success = await state.createNetworkTemplate(data);
                    }
                    if (success) {
                      _loadAllData();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
                  child: Text(Translation.getText(state.locale, 'common.confirm')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deployTemplate(Map<String, dynamic> tmpl) {
    // Exposes a multi-select dialog for hosts
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        final hosts = state.hosts;
        final selectedHostIds = <int>[];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Deploy: ${tmpl['name']}'),
              content: SizedBox(
                width: double.maxFinite,
                height: 240,
                child: hosts.isEmpty
                    ? const Center(child: Text('No hosts available.'))
                    : ListView.builder(
                        itemCount: hosts.length,
                        itemBuilder: (c, idx) {
                          final h = hosts[idx];
                          final isSelected = selectedHostIds.contains(h.id);
                          return CheckboxListTile(
                            title: Text(h.name),
                            subtitle: Text(h.host),
                            value: isSelected,
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
                                  selectedHostIds.add(h.id);
                                } else {
                                  selectedHostIds.remove(h.id);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(Translation.getText(state.locale, 'common.cancel')),
                ),
                ElevatedButton(
                  onPressed: selectedHostIds.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final success = await state.batchApplyNetworkTemplate(tmpl['id'] as int, selectedHostIds);
                          if (success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Latency template deployed successfully!'), backgroundColor: Colors.green),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
                  child: const Text('Deploy'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteTemplate(Map<String, dynamic> tmpl) {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'common.confirmDelete')),
          content: Text('${tmpl['name']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await state.deleteNetworkTemplate(tmpl['id'] as int);
                if (success) {
                  _loadAllData();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  // UI tabs
  Widget _buildParamTab(AppState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(state.locale, 'system.settingsTitle'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFF5C35)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _sshTimeoutController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.sshTimeout')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _idleTimeoutController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.idleTimeout')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _maxConnController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.maxConnectionsPerUser')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _loginRateController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.loginRateLimit')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenExpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Token Expiration (Hours)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5C35),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              Translation.getText(state.locale, 'common.save'),
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab(AppState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // SMTP Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.email, color: Color(0xFFFF5C35)),
                      SizedBox(width: 8),
                      Text('SMTP Alerts Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _smtpServerController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpServer')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpPortController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpPort')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpUserController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpUser')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpPassword')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpFromController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpFrom')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _smtpToController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.smtpTo')),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _testEmail,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, side: const BorderSide(color: Color(0xFFFF5C35))),
                    child: Text(Translation.getText(state.locale, 'system.testEmail'), style: const TextStyle(color: Color(0xFFFF5C35))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Telegram Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.send, color: Color(0xFF2ED573)),
                      SizedBox(width: 8),
                      Text('Telegram Alerts Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tgTokenController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.telegramToken')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tgChatIdController,
                    decoration: InputDecoration(labelText: Translation.getText(state.locale, 'system.telegramChatId')),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _testTelegram,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, side: const BorderSide(color: Color(0xFF2ED573))),
                    child: Text(Translation.getText(state.locale, 'system.testTelegram'), style: const TextStyle(color: Color(0xFF2ED573))),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35), padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(Translation.getText(state.locale, 'common.save'), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDbTab(AppState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Database Backup Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(state.locale, 'system.backupTitle'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFF5C35)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translation.getText(state.locale, 'system.backupDesc'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _triggerBackup,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
                    icon: const Icon(Icons.backup, size: 16, color: Colors.black87),
                    label: Text(Translation.getText(state.locale, 'system.startBackup'), style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Database Maintenance Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translation.getText(state.locale, 'system.dbMaintenanceTitle'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2ED573)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translation.getText(state.locale, 'system.dbMaintenanceDesc'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Text('Database rows:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white.withOpacity(0.8))),
                  const SizedBox(height: 8),
                  if (_dbStats.isNotEmpty)
                    Table(
                      border: TableBorder.all(color: Colors.white10),
                      children: _dbStats.entries.map((entry) {
                        return TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.all(8), child: Text(entry.key, style: const TextStyle(fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(8), child: Text(entry.value.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF5C35)))),
                          ],
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pruneData,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    icon: const Icon(Icons.cleaning_services, size: 16),
                    label: Text(Translation.getText(state.locale, 'system.pruneMonitorData'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
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
        backgroundColor: const Color(0xFFFF5C35),
        mini: true,
        child: const Icon(Icons.add, color: Colors.black87),
      ),
      body: _templates.isEmpty
          ? const Center(child: Text('No templates configured', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _templates.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (ctx, idx) {
                final tmpl = _templates[idx];
                final colorHex = tmpl['indicator_color'] ?? '#64D2FF';
                Color chipColor = const Color(0xFFFF5C35);
                try {
                  chipColor = Color(int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));
                } catch (_) {}

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: chipColor.withOpacity(0.2),
                      child: Icon(Icons.speed, color: chipColor),
                    ),
                    title: Text(tmpl['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${tmpl['type']?.toUpperCase() ?? 'PING'} 鈥?${tmpl['target']} 鈥?Freq: ${tmpl['interval']}s'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_circle_right_outlined, color: Color(0xFF2ED573)),
                          onPressed: () => _deployTemplate(tmpl),
                          tooltip: 'Deploy Template',
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _showAddEditTemplateDialog(tmpl),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                          onPressed: () => _deleteTemplate(tmpl),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          color: Theme.of(context).cardColor,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: const Color(0xFFFF5C35),
            tabs: const [
              Tab(text: 'Settings'),
              Tab(text: 'Notify Channels'),
              Tab(text: 'DB maintenance'),
              Tab(text: 'Latency Templates'),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildParamTab(state),
                _buildChannelTab(state),
                _buildDbTab(state),
                _buildNetworkTab(state),
              ],
            ),
    );
  }
}
