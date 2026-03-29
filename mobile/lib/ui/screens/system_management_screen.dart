import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/system_provider.dart';
import '../../models/system_settings.dart';
import '../../l10n/app_localizations.dart';

class SystemManagementScreen extends StatefulWidget {
  const SystemManagementScreen({super.key});

  @override
  State<SystemManagementScreen> createState() => _SystemManagementScreenState();
}

class _SystemManagementScreenState extends State<SystemManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _timezoneController = TextEditingController();
  final _sshTimeoutController = TextEditingController();
  final _idleTimeoutController = TextEditingController();
  final _maxConnectionsController = TextEditingController();
  final _loginRateLimitController = TextEditingController();
  final _accessExpirationController = TextEditingController();
  final _refreshExpirationController = TextEditingController();
  final _smtpServerController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _smtpFromController = TextEditingController();
  final _smtpToController = TextEditingController();
  final _telegramBotTokenController = TextEditingController();
  final _telegramChatIdController = TextEditingController();
  final _notificationTemplateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SystemProvider>(context, listen: false).fetchSystemSettings();
    });
  }

  @override
  void dispose() {
    _timezoneController.dispose();
    _sshTimeoutController.dispose();
    _idleTimeoutController.dispose();
    _maxConnectionsController.dispose();
    _loginRateLimitController.dispose();
    _accessExpirationController.dispose();
    _refreshExpirationController.dispose();
    _smtpServerController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPasswordController.dispose();
    _smtpFromController.dispose();
    _smtpToController.dispose();
    _telegramBotTokenController.dispose();
    _telegramChatIdController.dispose();
    _notificationTemplateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final systemProvider = Provider.of<SystemProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    if (systemProvider.isLoading && systemProvider.settings == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.systemManagement)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (systemProvider.error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.systemManagement)),
        body: Center(child: Text(systemProvider.error!)),
      );
    }

    final settings = systemProvider.settings;

    if (settings != null) {
      // 初始化控制器值
      _timezoneController.text = settings.timezone;
      _sshTimeoutController.text = settings.sshTimeout;
      _idleTimeoutController.text = settings.idleTimeout;
      _maxConnectionsController.text = settings.maxConnectionsPerUser.toString();
      _loginRateLimitController.text = settings.loginRateLimit.toString();
      _accessExpirationController.text = settings.accessExpiration;
      _refreshExpirationController.text = settings.refreshExpiration;
      _smtpServerController.text = settings.smtpServer;
      _smtpPortController.text = settings.smtpPort;
      _smtpUserController.text = settings.smtpUser;
      _smtpPasswordController.text = settings.smtpPassword;
      _smtpFromController.text = settings.smtpFrom;
      _smtpToController.text = settings.smtpTo;
      _telegramBotTokenController.text = settings.telegramBotToken;
      _telegramChatIdController.text = settings.telegramChatID;
      _notificationTemplateController.text = settings.notificationTemplate;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.systemManagement),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 基本设置部分
              _buildSectionHeader(l10n.basicSettings),
              _buildBasicSettings(),
              
              const SizedBox(height: 24),
              
              // 邮件通知设置部分
              _buildSectionHeader(l10n.emailNotifications),
              _buildEmailSettings(),
              
              const SizedBox(height: 24),
              
              // Telegram通知设置部分
              _buildSectionHeader(l10n.telegramNotifications),
              _buildTelegramSettings(),
              
              const SizedBox(height: 24),
              
              // 数据库管理部分
              _buildSectionHeader(l10n.databaseManagement),
              _buildDatabaseManagement(),
              
              const SizedBox(height: 24),
              
              // 系统更新部分
              _buildSectionHeader(l10n.systemUpdates),
              _buildSystemUpdates(),
              
              const SizedBox(height: 24),
              
              // 保存按钮
              ElevatedButton(
                onPressed: systemProvider.isLoading 
                    ? null 
                    : () => _saveSettings(systemProvider),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Text(l10n.saveSettings),
                ),
              ),
              
              if (systemProvider.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    systemProvider.error!,
                    style: TextStyle(color: Colors.red[600]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBasicSettings() {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _timezoneController,
              decoration: InputDecoration(labelText: l10n.timezone),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sshTimeoutController,
              decoration: InputDecoration(labelText: l10n.sshTimeout),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _idleTimeoutController,
              decoration: InputDecoration(labelText: l10n.idleTimeout),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxConnectionsController,
              decoration: InputDecoration(labelText: l10n.maxConnectionsPerUser),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginRateLimitController,
              decoration: InputDecoration(labelText: l10n.loginRateLimit),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accessExpirationController,
              decoration: InputDecoration(labelText: l10n.accessExpiration),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _refreshExpirationController,
              decoration: InputDecoration(labelText: l10n.refreshExpiration),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailSettings() {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _smtpServerController,
              decoration: InputDecoration(labelText: l10n.smtpServer),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _smtpPortController,
              decoration: InputDecoration(labelText: l10n.smtpPort),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _smtpUserController,
              decoration: InputDecoration(labelText: l10n.smtpUser),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _smtpPasswordController,
              decoration: InputDecoration(labelText: l10n.smtpPassword),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _smtpFromController,
              decoration: InputDecoration(labelText: l10n.smtpFrom),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _smtpToController,
              decoration: InputDecoration(labelText: l10n.smtpTo),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l10n.smtpSkipVerify),
              value: _smtpSkipVerify,
              onChanged: (value) {
                setState(() {
                  _smtpSkipVerify = value;
                });
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _testEmail(),
              icon: const Icon(Icons.send),
              label: Text(l10n.testEmail),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelegramSettings() {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _telegramBotTokenController,
              decoration: InputDecoration(labelText: l10n.telegramBotToken),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _telegramChatIdController,
              decoration: InputDecoration(labelText: l10n.telegramChatId),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notificationTemplateController,
              decoration: InputDecoration(labelText: l10n.notificationTemplate),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _testTelegram(),
              icon: const Icon(Icons.send),
              label: Text(l10n.testTelegram),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseManagement() {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.databaseManagementDescription),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _backupDatabase(),
              icon: const Icon(Icons.backup),
              label: Text(l10n.backupDatabase),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _restoreDatabase(),
              icon: const Icon(Icons.restore),
              label: Text(l10n.restoreDatabase),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemUpdates() {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: () => _checkUpdate(),
              icon: const Icon(Icons.update),
              label: Text(l10n.checkUpdate),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _performUpdate(),
              icon: const Icon(Icons.download),
              label: Text(l10n.performUpdate),
            ),
          ],
        ),
      ),
    );
  }

  bool _smtpSkipVerify = false;

  void _saveSettings(SystemProvider systemProvider) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final request = UpdateSettingsRequest(
      timezone: _timezoneController.text,
      sshTimeout: _sshTimeoutController.text,
      idleTimeout: _idleTimeoutController.text,
      maxConnectionsPerUser: int.tryParse(_maxConnectionsController.text) ?? 10,
      loginRateLimit: int.tryParse(_loginRateLimitController.text) ?? 5,
      accessExpiration: _accessExpirationController.text,
      refreshExpiration: _refreshExpirationController.text,
      smtpServer: _smtpServerController.text,
      smtpPort: _smtpPortController.text,
      smtpUser: _smtpUserController.text,
      smtpPassword: _smtpPasswordController.text,
      smtpFrom: _smtpFromController.text,
      smtpTo: _smtpToController.text,
      smtpSkipVerify: _smtpSkipVerify,
      telegramBotToken: _telegramBotTokenController.text,
      telegramChatID: _telegramChatIdController.text,
      notificationTemplate: _notificationTemplateController.text,
    );

    final success = await systemProvider.updateSystemSettings(request);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.settingsSavedSuccessfully)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToSaveSettings)),
      );
    }
  }

  void _testEmail() async {
    final systemProvider = Provider.of<SystemProvider>(context, listen: false);
    
    final success = await systemProvider.testEmail(
      smtpServer: _smtpServerController.text,
      smtpPort: _smtpPortController.text,
      smtpUser: _smtpUserController.text,
      smtpPassword: _smtpPasswordController.text,
      smtpFrom: _smtpFromController.text,
      smtpTo: _smtpToController.text,
      smtpSkipVerify: _smtpSkipVerify,
    );
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.emailTestSentSuccessfully)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToSendEmailTest)),
      );
    }
  }

  void _testTelegram() async {
    final systemProvider = Provider.of<SystemProvider>(context, listen: false);
    
    final success = await systemProvider.testTelegram(
      telegramBotToken: _telegramBotTokenController.text,
      telegramChatID: _telegramChatIdController.text,
    );
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.telegramTestSentSuccessfully)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToSendTelegramTest)),
      );
    }
  }

  void _backupDatabase() async {
    final systemProvider = Provider.of<SystemProvider>(context, listen: false);
    final result = await systemProvider.backupDatabase();
    
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.databaseBackupCreated)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToCreateDatabaseBackup)),
      );
    }
  }

  void _restoreDatabase() async {
    // TODO: 实现数据库恢复功能
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('数据库恢复功能待实现')),
    );
  }

  void _checkUpdate() async {
    final systemProvider = Provider.of<SystemProvider>(context, listen: false);
    final updateInfo = await systemProvider.checkUpdate();
    
    if (updateInfo != null) {
      if (updateInfo.updateAvailable) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.updateAvailable),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${AppLocalizations.of(context)!.version}: ${updateInfo.version}'),
                  if (updateInfo.body != null) ...[
                    const SizedBox(height: 8),
                    Text(updateInfo.body!),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppLocalizations.of(context)!.close),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _performUpdate();
                  },
                  child: Text(AppLocalizations.of(context)!.updateNow),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.noUpdatesAvailable)),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.failedToCheckForUpdates)),
      );
    }
  }

  void _performUpdate() async {
    // TODO: 实现更新功能
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('系统更新功能待实现')),
    );
  }
}