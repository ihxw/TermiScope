import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import 'history_screen.dart';
import 'command_screen.dart';
import 'placeholder_screen.dart';
import 'settings/profile_screen.dart';
import 'settings/user_list_screen.dart';
import 'settings/system_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.more), automaticallyImplyLeading: false),
      body: ListView(
        children: [
          // 功能区
          _buildSectionHeader(context, l10n.features),
          _buildMenuItem(
            context,
            icon: Icons.history,
            title: l10n.history,
            onTap: () => _navigate(context, const HistoryScreen()),
          ),
          _buildMenuItem(
            context,
            icon: Icons.code,
            title: l10n.commands,
            onTap: () => _navigate(context, const CommandScreen()),
          ),
          _buildMenuItem(
            context,
            icon: Icons.video_library,
            title: l10n.recordings,
            onTap: () =>
                _navigate(context, PlaceholderScreen(title: l10n.recordings)),
          ),

          const Divider(height: 32),

          // 设置区
          _buildSectionHeader(context, l10n.settings),
          _buildMenuItem(
            context,
            icon: Icons.person,
            title: l10n.profile,
            onTap: () => _navigate(context, const ProfileScreen()),
          ),
          _buildMenuItem(
            context,
            icon: Icons.people,
            title: l10n.users,
            onTap: () => _navigate(context, const UserListScreen()),
          ),
          _buildMenuItem(
            context,
            icon: Icons.settings,
            title: l10n.system,
            onTap: () => _navigate(context, const SystemScreen()),
          ),

          const Divider(height: 32),

          // 退出登录
          _buildMenuItem(
            context,
            icon: Icons.logout,
            title: l10n.logout,
            iconColor: Colors.red,
            textColor: Colors.red,
            onTap: () async {
              await auth.logout();
              // AuthWrapper will handle redirection
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: textColor)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}
