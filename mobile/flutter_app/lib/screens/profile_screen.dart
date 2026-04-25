import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;

  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchProfile();
    await context.read<AppState>().fetchLoginHistory();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('个人资料'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _loadData,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '安全', icon: Icon(Icons.lock, size: 16)),
                Tab(text: '会话', icon: Icon(Icons.devices, size: 16)),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [_buildSecurityTab(state), _buildSessionsTab(state)],
                ),
        );
      },
    );
  }

  Widget _buildSecurityTab(AppState state) {
    final profile = state.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (profile != null) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF64D2FF),
                child: Text(
                  profile.username.isNotEmpty
                      ? profile.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    if (profile.email.isNotEmpty)
                      Text(profile.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      profile.role == 'admin' ? '管理员' : '普通用户',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                profile.twoFactorEnabled ? Icons.shield : Icons.shield_outlined,
                color: profile.twoFactorEnabled ? const Color(0xFF32D74B) : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                profile.twoFactorEnabled ? '两步验证已启用' : '两步验证未启用',
                style: TextStyle(
                  color: profile.twoFactorEnabled ? const Color(0xFF32D74B) : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const Divider(color: Color(0xFF2D2D2D)),
        const SizedBox(height: 16),
        const Text('修改密码', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 16),
        _buildPasswordField('当前密码', _currentPassCtrl),
        const SizedBox(height: 12),
        _buildPasswordField('新密码', _newPassCtrl),
        const SizedBox(height: 12),
        _buildPasswordField('确认新密码', _confirmPassCtrl),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF64D2FF),
            foregroundColor: Colors.black,
            minimumSize: const Size(double.infinity, 44),
          ),
          onPressed: () => _changePassword(state),
          child: const Text('修改密码'),
        ),
        const SizedBox(height: 16),
        const Text('提示：修改密码后，请重新登录。', style: TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 13),
    );
  }

  Future<void> _changePassword(AppState state) async {
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入的新密码不一致')),
      );
      return;
    }
    final success = await state.changePassword(
      _currentPassCtrl.text,
      _newPassCtrl.text,
    );
    if (success) {
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码修改成功，请重新登录。')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码修改失败，请检查当前密码。')),
      );
    }
  }

  Widget _buildSessionsTab(AppState state) {
    if (state.loginSessions.isEmpty) {
      return const Center(child: Text('暂无会话记录', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: state.loginSessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF2D2D2D)),
      itemBuilder: (context, index) {
        final session = state.loginSessions[index];
        final statusColor = session.status == 'Active'
            ? const Color(0xFF32D74B)
            : session.status == 'Revoked'
                ? Colors.red
                : Colors.grey;

        return ListTile(
          leading: Icon(
            session.isCurrent ? Icons.phone_iphone : Icons.computer,
            color: session.isCurrent ? const Color(0xFF64D2FF) : Colors.grey,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${session.ipAddress}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              if (session.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF64D2FF).withAlpha(51),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('当前', style: TextStyle(color: Color(0xFF64D2FF), fontSize: 9)),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                _shortenUA(session.userAgent),
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              Text(
                '${_formatDate(session.loginAt)}  •  ${session.status}',
                style: TextStyle(color: statusColor, fontSize: 10),
              ),
            ],
          ),
          trailing: !session.isCurrent
              ? TextButton(
                  onPressed: () => _revokeSession(state, session.jti),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('撤销', style: TextStyle(fontSize: 12)),
                )
              : null,
        );
      },
    );
  }

  Future<void> _revokeSession(AppState state, String jti) async {
    final success = await state.revokeSession(jti);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会话已撤销'), duration: Duration(seconds: 1)),
      );
    }
  }

  String _shortenUA(String ua) {
    if (ua.length > 50) return '${ua.substring(0, 50)}...';
    return ua;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
