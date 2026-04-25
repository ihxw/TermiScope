import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _urlController = TextEditingController();
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController();
  final _twoFactorController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _show2FA = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.apiService.baseUrl?.isNotEmpty == true) {
      _urlController.text = appState.apiService.baseUrl!;
    }
    final savedUsername = appState.apiService.savedUsername;
    if (savedUsername?.isNotEmpty == true) {
      _userController.text = savedUsername!;
      if (appState.apiService.decryptedPassword != null) {
        _passController.text = appState.apiService.decryptedPassword!;
      }
    }
  }

  void _login() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (url.isEmpty || user.isEmpty || pass.isEmpty) return;

    setState(() {
      _isLoading = true;
      _show2FA = false;
    });
    final result = await context.read<AppState>().login(url, user, pass, _rememberMe);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['requires_2fa'] == true) {
      setState(() => _show2FA = true);
      _twoFactorController.clear();
    } else if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? '登录失败，请检查 URL 和凭据。')),
      );
    }
  }

  void _verify2FA() async {
    final code = _twoFactorController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await context.read<AppState>().verify2faLogin(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('2FA 验证码错误，请重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.terminal, size: 80, color: Color(0xFF64D2FF)),
                const SizedBox(height: 24),
                const Text(
                  'TermiScope',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 48),
                _buildTextField('服务器主页 (例: http://192.168.1.10)', _urlController, Icons.cloud),
                const SizedBox(height: 16),
                _buildTextField('用户名', _userController, Icons.person),
                const SizedBox(height: 16),
                _buildTextField('密码', _passController, Icons.lock, obscureText: true),
                if (_show2FA) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64D2FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF64D2FF).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield, color: Color(0xFF64D2FF), size: 18),
                            SizedBox(width: 8),
                            Text('需要两步验证', style: TextStyle(color: Color(0xFF64D2FF), fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildTextField('验证码', _twoFactorController, Icons.pin),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      activeColor: const Color(0xFF64D2FF),
                      onChanged: (v) => setState(() => _rememberMe = v == true),
                    ),
                    const Text('记住我', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64D2FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : (_show2FA ? _verify2FA : _login),
                  child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : Text(_show2FA ? '验 证' : '连 接', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String hint, TextEditingController controller, IconData icon, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
