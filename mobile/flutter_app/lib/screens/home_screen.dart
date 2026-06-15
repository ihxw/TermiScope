import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../services/monitor_service.dart';
import '../widgets/antd/index.dart';
import 'command_templates_screen.dart';
import 'connection_history_screen.dart';
import 'file_transfer_screen.dart';
import 'host_management_screen.dart';
import 'monitor_tab.dart';
import 'profile_screen.dart';
import 'recording_management_screen.dart';
import 'terminal_tabs_screen.dart';
import 'user_management_screen.dart';
import 'system_management_screen.dart';
import '../utils/translation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  MonitorService? _monitorService;

  final List<_DashboardPage> _pages = const [
    _DashboardPage('Terminal', '终端', Icons.code, TerminalTabsScreen()),
    _DashboardPage(
        'MonitorDashboard', '监控', Icons.dashboard_outlined, MonitorTab()),
    _DashboardPage(
        'FileTransfer', '文件传输', Icons.swap_horiz, FileTransferScreen()),
    _DashboardPage(
        'HostManagement', '主机', Icons.storage_outlined, HostManagementScreen()),
    _DashboardPage(
        'ConnectionHistory', '历史', Icons.history, ConnectionHistoryScreen()),
    _DashboardPage('CommandManagement', '命令', Icons.bolt_outlined,
        CommandTemplatesScreen()),
    _DashboardPage('RecordingManagement', '录像', Icons.videocam_outlined,
        RecordingManagementScreen()),
    _DashboardPage(
        'UserManagement', '用户', Icons.groups_outlined, UserManagementScreen(),
        adminOnly: true),
    _DashboardPage('SystemManagement', '系统', Icons.settings_outlined,
        SystemManagementScreen(),
        adminOnly: true),
  ];

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.hosts.isEmpty) {
      appState.fetchHosts();
    }
    appState.fetchProfile();
    appState.fetchSystemInfo();
    _monitorService = MonitorService(appState);
    _monitorService?.connect();
  }

  @override
  void dispose() {
    _monitorService?.disconnect();
    super.dispose();
  }


  void _selectPage(int index) {
    setState(() => _currentIndex = index);
    Navigator.of(context).maybePop();
  }

  void _toggleTheme(AppState state) {
    state.updateThemeMode(
      state.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  void _toggleLocale(AppState state) {
    state.updateLocale(state.locale == 'zh' ? 'en' : 'zh');
  }

  Future<void> _logout(AppState state) async {
    await state.logout();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  String _t(AppState state, String key) =>
      Translation.getText(state.locale, key);

  String _pageLabel(AppState state, _DashboardPage page) {
    return switch (page.key) {
      'Terminal' => _t(state, 'nav.terminal'),
      'MonitorDashboard' => _t(state, 'nav.monitor'),
      'FileTransfer' => _t(state, 'nav.fileTransfer'),
      'HostManagement' => _t(state, 'nav.hosts'),
      'ConnectionHistory' => _t(state, 'nav.history'),
      'CommandManagement' => _t(state, 'nav.commands'),
      'RecordingManagement' => _t(state, 'nav.recordings'),
      'UserManagement' => _t(state, 'nav.users'),
      'SystemManagement' => _t(state, 'nav.system'),
      _ => page.label,
    };
  }

  Widget _buildBrand(BuildContext context) {
    final fg =
        AntdTokens.isDark(context) ? Colors.white : const Color(0xFF001529);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.code, size: 18, color: fg),
        const SizedBox(width: 8),
        Text(
          'TermiScope',
          style:
              TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
        ),
      ],
    );
  }

  Widget _buildDrawer(
      BuildContext context, AppState state, List<int> visibleIndexes) {
    final border = AntdTokens.isDark(context)
        ? AntdTokens.darkBorder
        : AntdTokens.lightHeaderBorder;
    final fg =
        AntdTokens.isDark(context) ? Colors.white : const Color(0xFF001529);

    return Drawer(
      width: 280,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: AntdTokens.headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: border)),
                color: AntdTokens.containerColor(context),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildBrand(context),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 18, color: fg),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: visibleIndexes.map((index) {
                  final page = _pages[index];
                  final selected = index == _currentIndex;
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      minLeadingWidth: 24,
                      selectedTileColor: AntdTokens.primary
                          .withAlpha(AntdTokens.isDark(context) ? 38 : 25),
                      leading: Icon(
                        page.icon,
                        size: 16,
                        color: selected
                            ? AntdTokens.primary
                            : AntdTokens.secondaryTextColor(context),
                      ),
                      title: Text(
                        _pageLabel(state, page),
                        style: TextStyle(
                          fontSize: 14,
                          color: selected ? AntdTokens.primary : null,
                        ),
                      ),
                      selected: selected,
                      onTap: () => _selectPage(index),
                    ),
                  );
                }).toList(),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(border: Border(top: BorderSide(color: border))),
              child: Text(
                '${_t(state, 'common.version')}: v1.0.0',
                style: const TextStyle(
                    fontSize: 12, color: AntdTokens.lightTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions(AppState state, bool isMobile) {
    final fg =
        AntdTokens.isDark(context) ? Colors.white : const Color(0xFF001529);
    final username = state.profile?.username ?? '';

    final userMenuItems = [
      AntdDropdownItem<String>(
        value: 'profile',
        label: _t(state, 'nav.profile'),
        icon: Icons.person_outline,
      ),
      const AntdDropdownItem<String>(
        value: 'divider',
        label: '',
        divider: true,
      ),
      AntdDropdownItem<String>(
        value: 'logout',
        label: _t(state, 'nav.logout'),
        icon: Icons.logout,
        danger: true,
      ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'v${state.backendVersion}',
              style: const TextStyle(
                fontSize: 12,
                color: AntdTokens.lightTextSecondary,
              ),
            ),
          ),
        AntdButton(
          type: AntdButtonType.link,
          size: AntdSize.small,
          onPressed: () => _toggleLocale(state),
          child: Text(state.locale == 'zh' ? 'EN' : '中文'),
        ),
        AntdButton(
          type: AntdButtonType.text,
          size: AntdSize.small,
          icon: state.themeMode == ThemeMode.dark
              ? Icons.lightbulb_outline
              : Icons.lightbulb,
          onPressed: () => _toggleTheme(state),
        ),
        AntdDropdown<String>(
          items: userMenuItems,
          onSelected: (key) {
            if (key == 'profile') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            } else if (key == 'logout') {
              _logout(state);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, size: 18, color: fg),
                if (!isMobile && username.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      username,
                      style: TextStyle(fontSize: 13, color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                Icon(Icons.keyboard_arrow_down, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopMenu(
    BuildContext context,
    AppState state,
    List<int> visibleIndexes,
  ) {
    final isDark = AntdTokens.isDark(context);
    return Expanded(
      child: Container(
        height: AntdTokens.headerHeight,
        margin: const EdgeInsets.only(left: 24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: visibleIndexes.map((index) {
              final page = _pages[index];
              final selected = index == _currentIndex;
              final color = selected
                  ? AntdTokens.primary
                  : isDark
                      ? Colors.white
                      : const Color(0xFF001529);
              return InkWell(
                onTap: () => _selectPage(index),
                child: Container(
                  height: AntdTokens.headerHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            selected ? AntdTokens.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(page.icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(
                        _pageLabel(state, page),
                        style: TextStyle(fontSize: 14, color: color),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final isAdmin = state.profile?.role == 'admin';
        final visibleIndexes = <int>[
          for (var i = 0; i < _pages.length; i++)
            if (!_pages[i].adminOnly || isAdmin) i,
        ];
        if (!visibleIndexes.contains(_currentIndex)) {
          _currentIndex = 0;
        }
        final width = MediaQuery.of(context).size.width;
        final isMobile = width <= AntdTokens.mobileBreakpoint;
        final border = AntdTokens.isDark(context)
            ? AntdTokens.darkBorder
            : AntdTokens.lightHeaderBorder;

        return Scaffold(
          drawer: _buildDrawer(context, state, visibleIndexes),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(AntdTokens.headerHeight),
            child: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Builder(
                builder: (appBarContext) => Container(
                  height: AntdTokens.headerHeight,
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 24),
                  decoration: BoxDecoration(
                    color: AntdTokens.containerColor(context),
                    border: Border(bottom: BorderSide(color: border)),
                  ),
                  child: Row(
                    children: [
                      if (isMobile)
                        GestureDetector(
                          onTap: () =>
                              Scaffold.of(appBarContext).openDrawer(),
                          child: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(Icons.menu, size: 20),
                          ),
                        ),
                      _buildBrand(context),
                      if (isMobile)
                        const Spacer()
                      else
                        _buildDesktopMenu(context, state, visibleIndexes),
                      _buildHeaderActions(state, isMobile),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: Container(
            color: AntdTokens.pageColor(context),
            child: Padding(
              padding: EdgeInsets.all(AntdTokens.contentPadding(context)),
              child: IndexedStack(
                index: _currentIndex,
                children: _pages.map((page) => page.child).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardPage {
  final String key;
  final String label;
  final IconData icon;
  final Widget child;
  final bool adminOnly;

  const _DashboardPage(
    this.key,
    this.label,
    this.icon,
    this.child, {
    this.adminOnly = false,
  });
}
