import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';
import 'package:mobile/l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url =
        prefs.getString(AppConstants.serverUrlKey) ??
        AppConstants.defaultServerUrl;
    setState(() {
      _serverController.text = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${AppLocalizations.of(context)!.appTitle} ${AppLocalizations.of(context)!.login}',
        ),
        actions: [
          // Removed separate settings button as it is now inline
        ],
      ),
      body: SingleChildScrollView(
        // Added scroll view to avoid overflow
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.terminal, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            if (auth.error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(8),
                color: Colors.red.withOpacity(0.1),
                child: Text(
                  auth.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            // Server URL Input
            TextField(
              controller: _serverController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.serverHost,
                hintText: 'http://127.0.0.1:3000',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.username,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        // Save Server URL
                        final prefs = await SharedPreferences.getInstance();
                        final url = _serverController.text.trim();
                        if (url.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.of(context)!.enterServerUrl,
                              ),
                            ),
                          );
                          return;
                        }
                        await prefs.setString(AppConstants.serverUrlKey, url);

                        // Login
                        await auth.login(
                          _usernameController.text,
                          _passwordController.text,
                        );
                      },
                style: ElevatedButton.styleFrom(elevation: 2),
                child: auth.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(AppLocalizations.of(context)!.login),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
