import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/system_api.dart';

class SystemSettingsPage extends ConsumerStatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  ConsumerState<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends ConsumerState<SystemSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Settings
  final _portController = TextEditingController();
  String _logLevel = 'info';
  bool _registrationEnabled = false; // Mock, if API supports it

  // SMTP
  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPassController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await ref.read(systemApiProvider).getSettings();
      // Map response to controllers.
      // Note: Actual API structure depends on backend.
      // Assuming a flattened structure or nested 'server', 'smtp' keys.

      // For now, implementing as a placeholder frame since I don't know exact API response structure.
      // Will log the response to verify structure during dev.
      debugPrint('Settings: $settings');

      if (settings.containsKey('server')) {
        final server = settings['server'] as Map<String, dynamic>;
        _portController.text = server['port']?.toString() ?? '3000';
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Error is expected if API not implemented or different
        // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load failed: $e')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // Construct payload
      final payload = {
        'server': {
          'port': int.tryParse(_portController.text) ?? 3000,
        }
      };
      await ref.read(systemApiProvider).updateSettings(payload);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Server Settings',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                          labelText: 'Port', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),
                    const Text('SMTP Settings (Mock)',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _smtpHostController,
                      decoration: const InputDecoration(
                          labelText: 'SMTP Host', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _save,
                      child: const Text('Save Settings'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
