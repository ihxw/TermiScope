import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../screens/host_list_screen.dart';
import '../screens/monitor_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../screens/history_screen.dart';
import '../screens/command_screen.dart';

import '../screens/settings/profile_screen.dart';
import '../screens/settings/user_list_screen.dart';
import '../screens/settings/system_screen.dart';
import '../screens/placeholder_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(
      context,
      listen: false,
    ); // No need to listen for user details updates here yet

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            accountName: const Text('Admin'), // TODO: Get from AuthProvider
            accountEmail: const Text('admin@termiscope.local'),
            currentAccountPicture: const CircleAvatar(
              child: Icon(Icons.person, size: 40),
            ),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context,
                  icon: Icons.dashboard,
                  title: AppLocalizations.of(context)!.monitor,
                  onTap: () => _navigate(context, const MonitorScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.computer,
                  title: AppLocalizations.of(context)!.hosts,
                  onTap: () => _navigate(context, const HostListScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.history,
                  title: AppLocalizations.of(context)!.history,
                  onTap: () => _navigate(context, const HistoryScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.code,
                  title: AppLocalizations.of(context)!.commands,
                  onTap: () => _navigate(context, const CommandScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.video_library,
                  title: AppLocalizations.of(context)!.recordings,
                  onTap: () => _navigate(
                    context,
                    PlaceholderScreen(
                      title: AppLocalizations.of(context)!.recordings,
                    ),
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
                  child: Text(
                    AppLocalizations.of(context)!.settings,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.person,
                  title: AppLocalizations.of(context)!.profile,
                  onTap: () => _navigate(context, const ProfileScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.people,
                  title: AppLocalizations.of(context)!.users,
                  onTap: () => _navigate(context, const UserListScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.settings,
                  title: AppLocalizations.of(context)!.system,
                  onTap: () => _navigate(context, const SystemScreen()),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(
              AppLocalizations.of(context)!.logout,
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () async {
              // Close drawer first
              Navigator.pop(context);
              await auth.logout();
              // AuthWrapper will handle redirection to Login
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(leading: Icon(icon), title: Text(title), onTap: onTap);
  }

  void _navigate(BuildContext context, Widget screen) {
    // Close drawer
    Navigator.pop(context);

    // Check if we are already on this screen to avoid duplicate routes
    // For simplicity in this iteration, we just pushReplacement to avoid stack buildup
    // Ideally use named routes or a proper router
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }
}
