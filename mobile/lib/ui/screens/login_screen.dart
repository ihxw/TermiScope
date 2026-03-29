import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../core/constants.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _requires2FA = false;
  final String _tempUserId = '';
  final String _tempToken = '';
  final _twoFAController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AppConstants.serverUrlKey) ?? AppConstants.defaultServerUrl;
    setState(() {
      _serverController.text = url;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    _twoFAController.dispose();
    super.dispose();
  }

  Future<void> _performLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Save Server URL
    final prefs = await SharedPreferences.getInstance();
    final url = _serverController.text.trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.enterServerUrl)),
        );
      }
      return;
    }
    await prefs.setString(AppConstants.serverUrlKey, url);

    // Check if 2FA is required
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final requires2FA = await authProvider.requires2FA(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (requires2FA) {
      // 2FA is required, show 2FA input
      setState(() {
        _requires2FA = true;
      });
    } else {
      // Normal login
      final success = await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (success && mounted) {
        // Navigate to dashboard
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    }
  }

  Future<void> _verify2FA() async {
    if (_twoFAController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter 2FA code')),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.loginWith2FA(
      _tempUserId,
      _twoFAController.text.trim(),
      _tempToken,
    );

    if (success && mounted) {
      // Navigate to dashboard
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.appTitle} ${l10n.login}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              
              if (auth.error != null && !_requires2FA)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),

              // Server URL Input
              TextFormField(
                controller: _serverController,
                decoration: InputDecoration(
                  labelText: l10n.serverHost,
                  hintText: 'http://127.0.0.1:3000',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter server URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              if (!_requires2FA) ...[
                // Username Input
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.username,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password Input
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter password';
                    }
                    return null;
                  },
                ),
              ] else 
                // 2FA Input
                Column(
                  children: [
                    Text(
                      'Two-Factor Authentication Required',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _twoFAController,
                      decoration: InputDecoration(
                        labelText: '2FA Code',
                        hintText: 'Enter 6-digit code',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.code),
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      validator: (value) {
                        if (value == null || value.length != 6) {
                          return 'Please enter 6-digit code';
                        }
                        return null;
                      },
                    ),
                  ],
                ),

              const SizedBox(height: 24),

              if (!_requires2FA)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _performLogin,
                    style: ElevatedButton.styleFrom(elevation: 2),
                    child: auth.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(l10n.login),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _verify2FA,
                        style: ElevatedButton.styleFrom(elevation: 2),
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Verify 2FA'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: auth.isLoading ? null : () {
                          setState(() {
                            _requires2FA = false;
                            _twoFAController.clear();
                          });
                        },
                        child: Text('Back'),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),
              
              // Forgot Password Link
              if (!_requires2FA)
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/forgot-password');
                  },
                  child: Text('Forgot Password?'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}