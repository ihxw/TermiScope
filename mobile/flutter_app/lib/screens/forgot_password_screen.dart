import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import 'auth_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  String _error = '';
  String _success = '';

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
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = '';
      _success = '';
    });
    final state = context.read<AppState>();
    final result = await state.forgotPassword(
      _urlController.text.trim(),
      _emailController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      setState(() {
        _success = Translation.getText(state.locale, 'auth.resetEmailSent');
        _emailController.clear();
      });
      return;
    }
    setState(() => _error = result['error']?.toString() ?? '提交失败');
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
            const SizedBox(height: 8),
            Text(
              Translation.getText(state.locale, 'auth.resetPasswordDesc'),
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
              controller: _emailController,
              placeholder: 'example@email.com',
              prefixIcon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
            ),
            if (_success.isNotEmpty) ...[
              const SizedBox(height: 12),
              AntdAlert(
                type: AntdAlertType.success,
                message: _success,
                showIcon: true,
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              AntdAlert(
                type: AntdAlertType.error,
                message: _error,
                showIcon: true,
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
              child: Text(
                  Translation.getText(state.locale, 'auth.sendResetEmail')),
            ),
            const SizedBox(height: 8),
            Center(
              child: AntdButton(
                type: AntdButtonType.link,
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed('/login'),
                child: Text(
                  Translation.getText(state.locale, 'common.backToLogin'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
