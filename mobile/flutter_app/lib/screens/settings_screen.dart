import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import 'host_edit_dialog.dart';
import 'connection_history_screen.dart';
import 'command_templates_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          body: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                color: const Color(0xFF2D2D2D),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF64D2FF),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.apiService.savedUsername ?? 'User',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            state.apiService.baseUrl ?? 'Not connected',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Settings List
              Expanded(
                child: ListView(
                  children: [
                    // Terminal Settings Section
                    _buildSectionHeader('Terminal'),
                    ListTile(
                      leading: const Icon(Icons.text_fields, color: Colors.grey),
                      title: const Text('字体大小'),
                      subtitle: Text('${state.terminalFontSize.toStringAsFixed(1)}px'),
                      onTap: () => _showFontSizeDialog(context, state),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),
                    ListTile(
                      leading: const Icon(Icons.palette, color: Colors.grey),
                      title: const Text('主题'),
                      subtitle: const Text('深色模式 (固定)'),
                      enabled: false,
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),

                    // Host Management Section
                    _buildSectionHeader('主机管理'),
                    ListTile(
                      leading: const Icon(Icons.add, color: Color(0xFF64D2FF)),
                      title: const Text('添加主机'),
                      onTap: () => _showAddHostDialog(context, state),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),
                    ListTile(
                      leading: const Icon(Icons.list, color: Colors.grey),
                      title: const Text('管理主机'),
                      subtitle: Text('${state.hosts.length} 个主机'),
                      onTap: () => _navigateToHostList(context, state),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),

                    // Features
                    _buildSectionHeader('功能'),
                    ListTile(
                      leading: const Icon(Icons.history, color: Colors.grey),
                      title: const Text('连接历史'),
                      onTap: () => _navigateTo(context, const ConnectionHistoryScreen()),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),
                    ListTile(
                      leading: const Icon(Icons.code, color: Colors.grey),
                      title: const Text('命令模板'),
                      onTap: () => _navigateTo(context, const CommandTemplatesScreen()),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),

                    // Account
                    _buildSectionHeader('账户'),
                    ListTile(
                      leading: const Icon(Icons.person_outline, color: Colors.grey),
                      title: const Text('个人资料'),
                      onTap: () => _navigateTo(context, const ProfileScreen()),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                      onTap: () => _logout(context, state),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64D2FF),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context, AppState state) {
    double tempSize = state.terminalFontSize;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title: const Text('终端字体大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${tempSize.toStringAsFixed(1)}px', style: const TextStyle(color: Colors.white)),
              Slider(
                value: tempSize,
                min: 10,
                max: 24,
                divisions: 28,
                activeColor: const Color(0xFF64D2FF),
                onChanged: (v) => setDialogState(() => tempSize = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                state.updateTerminalFontSize(tempSize);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF)),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHostDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => const HostEditDialog(),
    );
  }

  void _navigateToHostList(BuildContext context, AppState state) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HostListScreen(),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _logout(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await state.logout();
              if (context.mounted) {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context); // Go back to login
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

// Host List Screen
class HostListScreen extends StatelessWidget {
  const HostListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('管理主机'),
            backgroundColor: const Color(0xFF2D2D2D),
          ),
          body: state.hosts.isEmpty
              ? const Center(
                  child: Text('没有主机', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: state.hosts.length,
                  itemBuilder: (context, index) {
                    final host = state.hosts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: host.hostType == 'monitor_only'
                            ? const Color(0xFF32D74B)
                            : const Color(0xFF64D2FF),
                        child: Icon(
                          host.hostType == 'monitor_only'
                              ? Icons.monitor_heart
                              : Icons.terminal,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(host.name),
                      subtitle: Text('${host.host}:${host.port}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (host.hostType == 'ssh')
                            IconButton(
                              icon: const Icon(Icons.wifi_find, size: 18),
                              tooltip: '测试连接',
                              onPressed: () => _testHost(context, state, host),
                            ),
                          if (host.monitorEnabled) ...[
                            IconButton(
                              icon: const Icon(Icons.arrow_circle_down, size: 18),
                              tooltip: '部署监控',
                              onPressed: () => _deployMonitorAgent(context, state, host),
                            ),
                            IconButton(
                              icon: const Icon(Icons.stop_circle, size: 18, color: Colors.orange),
                              tooltip: '停止监控',
                              onPressed: () => _stopMonitorAgent(context, state, host),
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showEditHostDialog(context, state, host),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () => _confirmDeleteHost(context, state, host),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _testHost(BuildContext context, AppState state, Host host) async {
    final result = await state.testHostConnection(host.id.toString());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? ''),
          backgroundColor: result['success'] == true
              ? const Color(0xFF32D74B)
              : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _deployMonitorAgent(BuildContext context, AppState state, Host host) async {
    final success = await state.deployMonitorAgent(host.id.toString());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '监控代理已部署' : '部署失败'),
          backgroundColor: success ? const Color(0xFF32D74B) : Colors.red,
        ),
      );
    }
  }

  void _stopMonitorAgent(BuildContext context, AppState state, Host host) async {
    final success = await state.stopMonitorAgent(host.id.toString());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '监控代理已停止' : '停止失败'),
          backgroundColor: success ? const Color(0xFF32D74B) : Colors.red,
        ),
      );
    }
  }

  void _showEditHostDialog(BuildContext context, AppState state, Host host) {
    showDialog(
      context: context,
      builder: (ctx) => HostEditDialog(host: {
        'id': host.id,
        'name': host.name,
        'host': host.host,
        'port': host.port,
        'username': host.username,
        'host_type': host.hostType,
        'monitor_enabled': host.monitorEnabled,
        'net_traffic_limit': host.netTrafficLimit,
        'net_reset_day': host.netResetDay,
        'net_traffic_counter_mode': host.netTrafficCounterMode,
        'net_traffic_used_adjustment': host.netTrafficUsedAdjustment,
        'expiration_date': host.expirationDate,
        'billing_amount': host.billingAmount,
        'billing_period': host.billingPeriod,
        'currency': host.currency,
        'sort_order': host.sortOrder,
      }),
    );
  }

  void _confirmDeleteHost(BuildContext context, AppState state, Host host) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('删除主机'),
        content: Text('确定要删除 "${host.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await state.deleteHost(host.id.toString());
              if (context.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
