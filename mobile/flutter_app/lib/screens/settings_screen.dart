import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'host_edit_dialog.dart';

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

                    // Connection Section
                    _buildSectionHeader('连接'),
                    ListTile(
                      leading: const Icon(Icons.cloud, color: Colors.grey),
                      title: const Text('服务器地址'),
                      subtitle: Text(state.apiService.baseUrl ?? '未设置'),
                      onTap: () => _showServerUrlDialog(context, state),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),
                    ListTile(
                      leading: const Icon(Icons.key, color: Colors.grey),
                      title: const Text('密码'),
                      subtitle: Text(state.apiService.decryptedPassword != null ? '已保存' : '未保存'),
                      onTap: () => _showPasswordDialog(context, state),
                    ),
                    const Divider(height: 1, color: Color(0xFF2D2D2D)),

                    // Account Section
                    _buildSectionHeader('账户'),
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
      builder: (ctx) => AlertDialog(
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
              onChanged: (v) => setState(() => tempSize = v),
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

  void _showServerUrlDialog(BuildContext context, AppState state) {
    final controller = TextEditingController(text: state.apiService.baseUrl ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('服务器地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.10',
            hintStyle: TextStyle(color: Colors.grey),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              state.apiService.baseUrl = controller.text.trim();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('服务器地址已更新')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, AppState state) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('保存密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('输入密码以保存（加密存储）', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '密码',
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.lock, color: Colors.grey),
              ),
              style: const TextStyle(color: Colors.white),
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
              if (passwordController.text.isNotEmpty) {
                state.apiService.saveSettings(
                  state.apiService.baseUrl ?? '',
                  state.apiService.token ?? '',
                  password: passwordController.text,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码已保存')),
                );
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF)),
            child: const Text('保存'),
          ),
        ],
      ),
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
                        backgroundColor: host['host_type'] == 'monitor_only'
                            ? const Color(0xFF32D74B)
                            : const Color(0xFF64D2FF),
                        child: Icon(
                          host['host_type'] == 'monitor_only'
                              ? Icons.monitor_heart
                              : Icons.terminal,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(host['name'] ?? 'Unnamed'),
                      subtitle: Text(host['host'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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

  void _showEditHostDialog(BuildContext context, AppState state, Map<String, dynamic> host) {
    showDialog(
      context: context,
      builder: (ctx) => HostEditDialog(host: host),
    );
  }

  void _confirmDeleteHost(BuildContext context, AppState state, Map<String, dynamic> host) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('删除主机'),
        content: Text('确定要删除 "${host['name']}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await state.deleteHost(host['id'].toString());
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
