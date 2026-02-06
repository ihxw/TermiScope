import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/settings_service.dart';
import 'package:mobile/l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late SettingsService _settingsService;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService(
      Provider.of<ApiService>(context, listen: false),
    );
  }

  void _showChangePasswordDialog() {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final cfmCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.changePassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: curCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.currentPassword,
                ),
              ),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.newPassword,
                ),
              ),
              TextField(
                controller: cfmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.confirmPassword,
                ),
              ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      if (newCtrl.text != cfmCtrl.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context)!.passwordsDoNotMatch,
                            ),
                          ),
                        );
                        return;
                      }
                      setState(() => loading = true);
                      try {
                        await _settingsService.changePassword(
                          curCtrl.text,
                          newCtrl.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(context)!.passwordChanged,
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setState(() => loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${AppLocalizations.of(context)!.error}: $e',
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 40,
              child: Icon(Icons.person, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoTile(
            AppLocalizations.of(context)!.username,
            user?.username ?? '-',
          ),
          _buildInfoTile(
            AppLocalizations.of(context)!.email,
            user?.email ?? '-',
          ),
          _buildInfoTile(AppLocalizations.of(context)!.role, user?.role ?? '-'),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock),
            title: Text(AppLocalizations.of(context)!.changePassword),
            onTap: _showChangePasswordDialog,
          ),
          const ListTile(
            leading: Icon(Icons.security, color: Colors.grey),
            title: Text(
              'Two-Factor Authentication',
              style: TextStyle(color: Colors.grey),
            ),
            subtitle: Text('Not supported on mobile yet'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return ListTile(
      title: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
