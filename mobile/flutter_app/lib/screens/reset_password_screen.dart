import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import 'auth_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _urlController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String _error = '';

  String get _token => Uri.base.queryParameters['token'] ?? '';

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
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    if (_token.isEmpty) {
      setState(() =>
          _error = Translation.getText(state.locale, 'auth.invalidToken'));
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() =>
          _error = Translation.getText(state.locale, 'auth.passwordMismatch'));
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    final result = await state.resetPassword(
      _urlController.text.trim(),
      _token,
      _passwordController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translation.getText(state.locale, 'auth.passwordResetSuccess'),
          ),
        ),
      );
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }
    setState(() => _error = result['error']?.toString() ?? '重置失败');
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
              Translation.getText(state.locale, 'auth.resetPassword'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            AntdInput(
              controller: _urlController,
              placeholder: '服务器主页 (例: http://192.168.1.10)',
              prefixIcon: Icons.cloud,
            ),
            const SizedBox(height: 12),
            AntdPasswordInput(
              controller: _passwordController,
              placeholder: Translation.getText(
                  state.locale, 'auth.newPasswordPlaceholder'),
              prefixIcon: Icons.lock,
            ),
            const SizedBox(height: 12),
            AntdPasswordInput(
              controller: _confirmController,
              placeholder: Translation.getText(
                  state.locale, 'auth.confirmPasswordPlaceholder'),
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
            Row(
              children: [
                Expanded(
                  child: AntdButton(
                    type: AntdButtonType.primary,
                    size: AntdSize.large,
                    block: true,
                    loading: _loading,
                    onPressed: _loading ? null : _submit,
                    child: Text(Translation.getText(
                        state.locale, 'auth.resetPassword')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AntdButton(
                    size: AntdSize.large,
                    block: true,
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/login'),
                    child:
                        Text(Translation.getText(state.locale, 'common.cancel')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
