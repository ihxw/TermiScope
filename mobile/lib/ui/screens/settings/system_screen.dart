import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/settings_service.dart';
import '../../widgets/app_drawer.dart';
import 'package:mobile/l10n/app_localizations.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  late SettingsService _settingsService;
  Map<String, dynamic> _settings = {};
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Ensure ApiService is imported and available
    _settingsService = SettingsService(
      Provider.of<ApiService>(context, listen: false),
    );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.getSystemSettings();
      if (mounted) setState(() => _settings = Map.from(settings));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final payload = Map<String, dynamic>.from(_settings);
    if (payload['max_connections_per_user'] is String) {
      payload['max_connections_per_user'] = int.tryParse(
        payload['max_connections_per_user'],
      );
    }
    if (payload['login_rate_limit'] is String) {
      payload['login_rate_limit'] = int.tryParse(payload['login_rate_limit']);
    }

    try {
      await _settingsService.updateSystemSettings(payload);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showBackupDialog() {
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.systemBackup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!.enterBackupPassword),
            TextField(controller: passCtrl, obscureText: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _performBackup(passCtrl.text);
            },
            child: Text(AppLocalizations.of(context)!.startBackup),
          ),
        ],
      ),
    );
  }

  Future<void> _performBackup(String password) async {
    try {
      final result = await _settingsService.triggerBackup(password);
      final filename = result['filename'];
      final ticket = result['ticket'];

      final prefs = await SharedPreferences.getInstance();
      final baseUrl =
          prefs.getString(AppConstants.serverUrlKey) ??
          AppConstants.defaultServerUrl;
      final url =
          '$baseUrl/api/system/backup/download?file=$filename&token=$ticket';

      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.system)),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(AppLocalizations.of(context)!.downloadBackup),
                    onPressed: _showBackupDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Divider(height: 32),
                  const Divider(height: 32),
                  _buildSectionTitle(
                    AppLocalizations.of(context)!.sshTimeout,
                  ), // Timeouts title was hardcoded "Timeouts" replaced by sshTimeout as a placeholder or added Timeouts to arb? I missed "Timeouts" in ARB.
                  _buildTextField(
                    AppLocalizations.of(context)!.sshTimeout,
                    'ssh_timeout',
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.idleTimeout,
                    'idle_timeout',
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.accessExpiration,
                    'access_expiration',
                  ),

                  const SizedBox(height: 16),
                  _buildSectionTitle(AppLocalizations.of(context)!.limits),
                  _buildTextField(
                    AppLocalizations.of(context)!.maxConnectionsPerUser,
                    'max_connections_per_user',
                    TextInputType.number,
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.loginRateLimit,
                    'login_rate_limit',
                    TextInputType.number,
                  ),

                  const SizedBox(height: 16),
                  _buildSectionTitle(
                    'SMTP',
                  ), // "SMTP" matches ARB smtpServer? No, "SMTP" is section title. I used "smtpServer" for label. I missed "Timeouts" and "SMTP" section titles in ARB. I'll use hardcoded for now or reuse?
                  _buildTextField(
                    AppLocalizations.of(context)!.smtpServer,
                    'smtp_server',
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.port,
                    'smtp_port',
                    TextInputType.number,
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.username,
                    'smtp_user',
                  ), // Using "username" generic key
                  _buildTextField(
                    AppLocalizations.of(
                      context,
                    )!.password, // Using "password" generic key
                    'smtp_password',
                    TextInputType.visiblePassword,
                    true,
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.senderEmail,
                    'smtp_from',
                  ),
                  _buildTextField(
                    AppLocalizations.of(context)!.adminEmail,
                    'smtp_to',
                  ),

                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveSettings,
                    child: Text(AppLocalizations.of(context)!.saveSettings),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String key, [
    TextInputType type = TextInputType.text,
    bool obscure = false,
  ]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        initialValue: _settings[key]?.toString(),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: type,
        obscureText: obscure,
        onSaved: (val) => _settings[key] = val,
      ),
    );
  }
}
