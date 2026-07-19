import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import 'auth_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _frontendVersion = '1.7.38';

  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _twoFactorController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _show2FA = false;
  String _error = '';

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

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final url = _urlController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (url.isEmpty || user.isEmpty || pass.isEmpty) {
      setState(() => _error = '请输入服务器地址、用户名和密码。');
      return;
    }

    setState(() {
      _isLoading = true;
      _show2FA = false;
      _error = '';
    });
    final result =
        await context.read<AppState>().login(url, user, pass, _rememberMe);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['requires_2fa'] == true) {
      setState(() => _show2FA = true);
      _twoFactorController.clear();
    } else if (!result['success']) {
      setState(() => _error = result['error'] ?? '登录失败，请检查 URL 和凭据。');
    }
  }

  Future<void> _verify2FA() async {
    final code = _twoFactorController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    final success = await context.read<AppState>().verify2faLogin(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      setState(() => _error = '2FA 验证码错误，请重试。');
    }
  }

  void _backToLogin() {
    setState(() {
      _show2FA = false;
      _error = '';
      _twoFactorController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final width = MediaQuery.sizeOf(context).width;
        final titleGap = width <= AntdTokens.smallMobileBreakpoint
            ? 20.0
            : (width <= AntdTokens.mobileBreakpoint ? 24.0 : 32.0);
        final formGap = width <= AntdTokens.mobileBreakpoint ? 12.0 : 16.0;
        return AuthScaffold(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthBranding(),
              SizedBox(height: titleGap),
              if (!_show2FA)
                ..._buildLoginForm(state, formGap)
              else
                ..._build2FAForm(state),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                AntdAlert(
                  type: AntdAlertType.error,
                  message: _error,
                  closable: true,
                  onClose: () => setState(() => _error = ''),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'v$_frontendVersion',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AntdTokens.lightTextSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildLoginForm(AppState state, double formGap) {
    return [
      AntdFormItem(
        label: state.locale == 'zh' ? '服务器主页' : 'Server URL',
        required: true,
        child: AntdInput(
          controller: _urlController,
          placeholder: 'http://192.168.1.10',
          prefixIcon: Icons.cloud_outlined,
        ),
      ),
      SizedBox(height: formGap),
      AntdFormItem(
        label: Translation.getText(state.locale, 'auth.username'),
        required: true,
        child: AntdInput(
          controller: _userController,
          placeholder:
              Translation.getText(state.locale, 'auth.usernamePlaceholder'),
          prefixIcon: Icons.person_outline,
        ),
      ),
      SizedBox(height: formGap),
      AntdFormItem(
        label: Translation.getText(state.locale, 'auth.password'),
        required: true,
        child: AntdPasswordInput(
          controller: _passController,
          placeholder:
              Translation.getText(state.locale, 'auth.passwordPlaceholder'),
          prefixIcon: Icons.lock_outline,
          onSubmitted: (_) => _login(),
        ),
      ),
      SizedBox(height: formGap),
      SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: AntdTokens.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(() => _rememberMe = v == true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translation.getText(state.locale, 'auth.rememberMe'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            AntdButton(
              type: AntdButtonType.link,
              size: AntdSize.small,
              onPressed: () =>
                  Navigator.of(context).pushNamed('/forgot-password'),
              child: Text(
                Translation.getText(state.locale, 'auth.forgotPassword'),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: formGap),
      AntdButton(
        type: AntdButtonType.primary,
        size: AntdSize.middle,
        block: true,
        loading: _isLoading,
        onPressed: _isLoading ? null : _login,
        child: Text(Translation.getText(state.locale, 'auth.login')),
      ),
    ];
  }

  List<Widget> _build2FAForm(AppState state) {
    return [
      const AntdAlert(
        type: AntdAlertType.info,
        message: '需要两步验证',
        description: '请输入认证器应用中的验证码或备用恢复码。',
      ),
      const SizedBox(height: 12),
      const Text(
        '请妥善保存备用恢复码，丢失后可能无法登录。',
        style: TextStyle(color: AntdTokens.error, fontSize: 12),
      ),
      const SizedBox(height: 16),
      AntdInput(
        controller: _twoFactorController,
        placeholder: '验证码',
        prefixIcon: Icons.shield,
        onSubmitted: (_) => _verify2FA(),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: AntdButton(
              type: AntdButtonType.primary,
              size: AntdSize.large,
              block: true,
              loading: _isLoading,
              onPressed: _isLoading ? null : _verify2FA,
              child: const Text('验证'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AntdButton(
              size: AntdSize.large,
              block: true,
              onPressed: _isLoading ? null : _backToLogin,
              child: Text(Translation.getText(state.locale, 'common.back')),
            ),
          ),
        ],
      ),
    ];
  }
}
