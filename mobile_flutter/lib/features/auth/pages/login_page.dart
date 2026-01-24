import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;

  // 2FA 相关
  bool _show2FADialog = false;
  int? _pending2FAUserId;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedServerUrl();
  }

  Future<void> _loadSavedServerUrl() async {
    final storage = ref.read(storageServiceProvider);
    await storage.init();
    final savedUrl = storage.getServerUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _serverController.text = savedUrl;
    } else {
      _serverController.text = 'http://localhost:3000';
    }
    _rememberMe = storage.getRememberMe();
    if (mounted) setState(() {});
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(authStateProvider.notifier).login(
            serverUrl: _serverController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            remember: _rememberMe,
          );

      if (result.requires2FA) {
        if (mounted) {
          setState(() {
            _show2FADialog = true;
            _pending2FAUserId = result.userId;
            _isLoading = false;
          });
        }
      } else if (result.success) {
        debugPrint('[Login] Login successful, navigating to /monitor');
        if (mounted) {
          setState(() => _isLoading = false);
          context.go('/monitor');
        }
      } else {
        debugPrint('[Login] Login returned success=false');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '登录失败：${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handle2FAVerify() async {
    if (_codeController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 6 位验证码')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(authStateProvider.notifier).verify2FA(
            userId: _pending2FAUserId!,
            code: _codeController.text,
          );

      if (mounted) {
        context.go('/monitor');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '验证失败：${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _show2FADialog ? _build2FAForm() : _buildLoginForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo 和标题
          const Icon(
            Icons.terminal,
            size: 64,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            'TermiScope',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '服务器监控与管理平台',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 48),

          // 服务器地址
          TextFormField(
            controller: _serverController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'http://192.168.1.1:8080',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入服务器地址';
              }
              if (!value.startsWith('http://') &&
                  !value.startsWith('https://')) {
                return '请输入有效的服务器地址';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 用户名
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入用户名';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // 密码
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),

          // 记住我
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() => _rememberMe = value ?? false);
                },
              ),
              const Text('记住登录状态'),
            ],
          ),
          const SizedBox(height: 16),

          // 错误信息
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            ),
          if (_errorMessage != null) const SizedBox(height: 16),

          // 登录按钮
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Widget _build2FAForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.security,
          size: 64,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          '两步验证',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          '请输入验证器应用中的 6 位验证码',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),

        // 验证码输入
        TextFormField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),

        // 错误信息
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppTheme.errorColor),
              textAlign: TextAlign.center,
            ),
          ),

        // 验证按钮
        ElevatedButton(
          onPressed: _isLoading ? null : _handle2FAVerify,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('验证'),
        ),
        const SizedBox(height: 16),

        // 返回按钮
        TextButton(
          onPressed: () {
            setState(() {
              _show2FADialog = false;
              _pending2FAUserId = null;
              _codeController.clear();
              _errorMessage = null;
            });
          },
          child: const Text('返回登录'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
