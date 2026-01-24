import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的密码不一致')),
                );
                return;
              }

              try {
                final authService = ref.read(authServiceProvider);
                await authService.changePassword(
                  currentPassword: currentController.text,
                  newPassword: newController.text,
                );
                Navigator.pop(context, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('修改失败: $e')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码修改成功')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户信息卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(
                      (user?.displayName ?? user?.username ?? 'U')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? user?.username ?? '未登录',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: user?.isAdmin == true
                                ? AppTheme.warningColor.withOpacity(0.2)
                                : AppTheme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user?.isAdmin == true ? '管理员' : '普通用户',
                            style: TextStyle(
                              fontSize: 12,
                              color: user?.isAdmin == true
                                  ? AppTheme.warningColor
                                  : AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 设置项
          _buildSettingItem(
            icon: Icons.lock_outline,
            title: '修改密码',
            onTap: _showChangePasswordDialog,
          ),

          if (user?.isAdmin == true) ...[
            _buildSettingItem(
              icon: Icons.people_outline,
              title: '用户管理',
              onTap: () => context.push('/users'),
            ),
            _buildSettingItem(
              icon: Icons.settings,
              title: '系统设置',
              onTap: () => context.push('/system/settings'),
            ),
            _buildSettingItem(
              icon: Icons.network_check, // or similar
              title: '网络模板',
              onTap: () => context.push('/system/templates'),
            ),
          ],

          _buildSettingItem(
            icon: Icons.security,
            title: '两步验证',
            subtitle: user?.twoFactorEnabled == true ? '已启用' : '未启用',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请在 Web 端设置两步验证')),
              );
            },
          ),
          const Divider(height: 32),
          _buildSettingItem(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: 'TermiScope v1.0.0',
            onTap: () {},
          ),
          const Divider(height: 32),
          _buildSettingItem(
            icon: Icons.logout,
            title: '退出登录',
            titleColor: AppTheme.errorColor,
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? Colors.grey.shade400),
      title: Text(
        title,
        style: TextStyle(color: titleColor),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade500),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
