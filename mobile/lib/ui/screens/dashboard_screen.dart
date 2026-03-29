import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import 'host_management_screen.dart';
import 'terminal_list_screen.dart';
import 'monitor_dashboard_screen.dart';
import 'user_management_screen.dart';
import 'system_management_screen.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const MonitorDashboardScreen(),
    const TerminalListScreen(),
    const HostManagementScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    // Add admin pages if user is admin
    final pages = List<Widget>.from(_pages);
    if (authProvider.isAdmin) {
      pages.addAll([
        const UserManagementScreen(),
        const SystemManagementScreen(),
      ]);
    }

    // Navigation destinations based on user role
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.dashboard),
        label: l10n.monitor,
      ),
      NavigationDestination(
        icon: const Icon(Icons.terminal),
        label: l10n.terminal,
      ),
      NavigationDestination(
        icon: const Icon(Icons.computer),
        label: l10n.hosts,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person),
        label: l10n.profile,
      ),
    ];

    if (authProvider.isAdmin) {
      destinations.addAll([
        NavigationDestination(
          icon: const Icon(Icons.people),
          label: l10n.users,
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings),
          label: l10n.system,
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          PopupMenuButton(
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.logout),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: destinations,
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();
  }
}