import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import 'auth_scaffold.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.apiService.baseUrl?.isNotEmpty == true) {
      _urlController.text = appState.apiService.baseUrl!;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error =
          Translation.getText(state.locale, 'auth.passwordMismatch'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await state.initializeSystem(
      _urlController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
      return;
    }
    setState(() => _error = result['error']?.toString() ?? '初始化失败');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) => AuthScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthBranding(),
            const SizedBox(height: 24),
            Text(
              Translation.getText(state.locale, 'setup.title'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              Translation.getText(state.locale, 'setup.description'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 24),
            AntdInput(
              controller: _urlController,
              placeholder: '服务器主页 (例: http://192.168.1.10)',
              prefixIcon: Icons.cloud,
            ),
            const SizedBox(height: 12),
            AntdInput(
              controller: _usernameController,
              placeholder: Translation.getText(
                  state.locale, 'setup.usernamePlaceholder'),
              prefixIcon: Icons.person,
            ),
            const SizedBox(height: 12),
            AntdPasswordInput(
              controller: _passwordController,
              placeholder: Translation.getText(
                  state.locale, 'setup.passwordPlaceholder'),
              prefixIcon: Icons.lock,
            ),
            const SizedBox(height: 12),
            AntdPasswordInput(
              controller: _confirmController,
              placeholder: Translation.getText(
                  state.locale, 'setup.confirmPlaceholder'),
              prefixIcon: Icons.lock,
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              AntdAlert(
                type: AntdAlertType.error,
                message: _error,
                closable: true,
                onClose: () => setState(() => _error = ''),
              ),
            ],
            const SizedBox(height: 16),
            AntdButton(
              type: AntdButtonType.primary,
              size: AntdSize.large,
              block: true,
              loading: _loading,
              onPressed: _loading ? null : _submit,
              child: Text(Translation.getText(state.locale, 'setup.submit')),
            ),
          ],
        ),
      ),
    );
  }
}
