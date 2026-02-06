import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../utils/responsive_layout.dart';
import '../widgets/app_header.dart';
import 'monitor_screen.dart';
import 'terminal_list_screen.dart';
import 'host_list_screen.dart';
import 'history_screen.dart';
import 'command_screen.dart';
import 'more_screen.dart';
import 'settings/profile_screen.dart';
import 'settings/user_list_screen.dart';
import 'settings/system_screen.dart';

/// 主导航Shell
/// PC端: 顶部Header + 内容区
/// 移动端: BottomNavigationBar + 内容区
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 移动端页面（4个底部导航项）
  late final List<Widget> _mobilePages;

  // PC端页面（完整导航）
  late final List<Widget> _desktopPages;

  @override
  void initState() {
    super.initState();
    _mobilePages = const [
      MonitorScreen(),
      TerminalListScreen(),
      HostListScreen(),
      MoreScreen(),
    ];

    _desktopPages = const [
      MonitorScreen(), // 0
      TerminalListScreen(), // 1
      HostListScreen(), // 2
      HistoryScreen(), // 3
      CommandScreen(), // 4
      UserListScreen(), // 5 (admin)
      SystemScreen(), // 6 (admin)
      ProfileScreen(), // 7
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);

    if (isMobile) {
      return _buildMobileLayout(context);
    } else {
      return _buildDesktopLayout(context);
    }
  }

  /// 移动端布局：底部导航
  Widget _buildMobileLayout(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex.clamp(0, _mobilePages.length - 1),
        children: _mobilePages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex.clamp(0, _mobilePages.length - 1),
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard),
            label: l10n.monitor,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.terminal),
            label: l10n.terminal,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.computer),
            label: l10n.hosts,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.more_horiz),
            label: l10n.more,
          ),
        ],
      ),
    );
  }

  /// PC端布局：顶部Header导航
  Widget _buildDesktopLayout(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isAdmin = auth.user?.role == 'admin';

    // 非管理员时限制可访问的页面索引
    int adjustedIndex = _currentIndex;
    if (!isAdmin && _currentIndex >= 5 && _currentIndex <= 6) {
      // 非管理员无法访问用户管理和系统设置
      adjustedIndex = 0;
    }

    return Scaffold(
      body: Column(
        children: [
          // 顶部Header
          AppHeader(
            currentIndex: adjustedIndex,
            onNavigate: (index) {
              setState(() => _currentIndex = index);
            },
          ),
          // 内容区
          Expanded(
            child: IndexedStack(
              index: adjustedIndex.clamp(0, _desktopPages.length - 1),
              children: _desktopPages,
            ),
          ),
        ],
      ),
    );
  }
}
