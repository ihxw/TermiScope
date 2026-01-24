import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/hosts_provider.dart';
import '../../../core/models/ssh_host.dart';
import '../../../shared/theme/app_theme.dart';

class HostEditPage extends ConsumerStatefulWidget {
  final int? hostId;

  const HostEditPage({super.key, this.hostId});

  @override
  ConsumerState<HostEditPage> createState() => _HostEditPageState();
}

class _HostEditPageState extends ConsumerState<HostEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _groupController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _authType = 'password';
  bool _isLoading = false;
  bool _obscurePassword = true;
  SshHost? _existingHost;

  bool get isEditing => widget.hostId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadHost();
    }
  }

  Future<void> _loadHost() async {
    setState(() => _isLoading = true);
    try {
      final hostService = ref.read(hostServiceProvider);
      final host = await hostService.getHost(widget.hostId!);
      setState(() {
        _existingHost = host;
        _nameController.text = host.name;
        _hostController.text = host.host;
        _portController.text = host.port.toString();
        _usernameController.text = host.username;
        _authType = host.authType;
        _groupController.text = host.groupName ?? '';
        _descriptionController.text = host.description ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<void> _saveHost() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final hostService = ref.read(hostServiceProvider);

      final data = {
        'name': _nameController.text.trim(),
        'host': _hostController.text.trim(),
        'port': int.parse(_portController.text),
        'username': _usernameController.text.trim(),
        'auth_type': _authType,
        'group_name': _groupController.text.trim().isEmpty
            ? null
            : _groupController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      };

      // 只有在修改了密码/密钥时才发送
      if (_authType == 'password' && _passwordController.text.isNotEmpty) {
        data['password'] = _passwordController.text;
      } else if (_authType == 'key' && _privateKeyController.text.isNotEmpty) {
        data['private_key'] = _privateKeyController.text;
      }

      if (isEditing) {
        await hostService.updateHost(widget.hostId!, data);
      } else {
        await hostService.createHost(data);
      }

      // 刷新列表
      ref.read(hostsStateProvider.notifier).loadHosts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? '主机已更新' : '主机已创建')),
        );
        context.go('/hosts');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑主机' : '新建主机'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/hosts'),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveHost,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _isLoading && isEditing && _existingHost == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 基本信息
                    _buildSectionTitle('基本信息'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '主机名称 *',
                        hintText: '例如: 生产服务器',
                      ),
                      validator: (v) => v?.isEmpty == true ? '请输入主机名称' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: '主机地址 *',
                              hintText: 'IP 或域名',
                            ),
                            validator: (v) =>
                                v?.isEmpty == true ? '请输入主机地址' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: '端口',
                            ),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v?.isEmpty == true) return '必填';
                              final port = int.tryParse(v!);
                              if (port == null || port < 1 || port > 65535) {
                                return '无效';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 认证信息
                    _buildSectionTitle('认证信息'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '用户名 *',
                        hintText: '例如: root',
                      ),
                      validator: (v) => v?.isEmpty == true ? '请输入用户名' : null,
                    ),
                    const SizedBox(height: 16),

                    // 认证方式切换
                    Row(
                      children: [
                        Expanded(
                          child: _AuthTypeButton(
                            label: '密码',
                            icon: Icons.password,
                            isSelected: _authType == 'password',
                            onTap: () => setState(() => _authType = 'password'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AuthTypeButton(
                            label: '密钥',
                            icon: Icons.key,
                            isSelected: _authType == 'key',
                            onTap: () => setState(() => _authType = 'key'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_authType == 'password')
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: isEditing ? '密码 (留空保持不变)' : '密码 *',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (v) {
                          if (!isEditing && (v?.isEmpty == true)) {
                            return '请输入密码';
                          }
                          return null;
                        },
                      )
                    else
                      TextFormField(
                        controller: _privateKeyController,
                        decoration: InputDecoration(
                          labelText: isEditing ? '私钥 (留空保持不变)' : '私钥 *',
                          hintText: '粘贴 SSH 私钥内容',
                        ),
                        maxLines: 5,
                        validator: (v) {
                          if (!isEditing && (v?.isEmpty == true)) {
                            return '请输入私钥';
                          }
                          return null;
                        },
                      ),
                    const SizedBox(height: 24),

                    // 其他信息
                    _buildSectionTitle('其他信息'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _groupController,
                      decoration: const InputDecoration(
                        labelText: '分组',
                        hintText: '例如: 生产环境',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: '备注',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade400,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _groupController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

class _AuthTypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AuthTypeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppTheme.primaryColor.withOpacity(0.2)
          : Colors.grey.shade800,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? AppTheme.primaryColor : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryColor : Colors.grey,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
