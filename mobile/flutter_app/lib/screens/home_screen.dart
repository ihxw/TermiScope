import 'dart:async';

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
  late final List<GlobalKey<NavigatorState>> _pageNavigatorKeys;
  MonitorService? _monitorService;
  Timer? _updatePollTimer;
  bool _updateProgressVisible = false;

  final List<_DashboardPage> _pages = const [
    _DashboardPage('Terminal', '终端', Icons.terminal, TerminalTabsScreen()),
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
    _pageNavigatorKeys = List.generate(
      _pages.length,
      (_) => GlobalKey<NavigatorState>(),
    );
    final appState = context.read<AppState>();
    if (appState.hosts.isEmpty) {
      appState.fetchHosts();
    }
    appState.fetchProfile();
    appState.fetchSystemInfo().then((_) => appState.checkForUpdates());
    _monitorService = MonitorService(appState);
    _monitorService?.connect();
  }

  @override
  void dispose() {
    _updatePollTimer?.cancel();
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

  void _startUpdatePolling(AppState state) {
    _updatePollTimer?.cancel();
    _updatePollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await state.pollUpdateStatus();
      if (!mounted) return;
      if (state.serverUpdateStatus == 'restarting') {
        _updatePollTimer?.cancel();
        _updatePollTimer =
            Timer.periodic(const Duration(seconds: 5), (_) async {
          await state.pollUpdateStatus();
          if (state.serverUpdateStatus == 'finished' ||
              state.serverUpdateStatus == 'error') {
            _updatePollTimer?.cancel();
          }
        });
      }
      if (state.serverUpdateStatus == 'finished' ||
          state.serverUpdateStatus == 'error') {
        _updatePollTimer?.cancel();
      }
    });
  }

  Future<void> _showUpdateConfirm(AppState state) async {
    final info = state.updateInfo;
    if (info == null) return;
    final version = info['version']?.toString() ?? '';
    final body = info['body']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AntdModal(
        width: 520,
        title: Text(
          _t(state, 'system.updateAvailable').replaceAll('{version}', version),
        ),
        okText: _t(state, 'common.updateNow'),
        cancelText: _t(state, 'common.cancel'),
        confirmLoading: state.updateLoading,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onOk: () => Navigator.of(dialogContext).pop(true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(state, 'system.updateDesc'),
              style: TextStyle(color: AntdTokens.textColor(context)),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AntdTokens.isDark(context)
                    ? const Color(0xFF303030)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AntdTokens.textColor(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _updateProgressVisible = true);
      _startUpdatePolling(state);
      await state.performServerUpdate();
    }
  }

  Widget _buildUpdateProgressModal(AppState state) {
    if (!_updateProgressVisible) return const SizedBox.shrink();
    final status = state.serverUpdateStatus;
    final isDone = status == 'finished';
    final isError = status == 'error';
    final statusText = switch (status) {
      'downloading' => _t(state, 'system.downloading'),
      'extracting' => _t(state, 'system.extracting'),
      'installing' => _t(state, 'system.installing'),
      'restarting' => _t(state, 'system.restarting'),
      'finished' => _t(state, 'system.updateSuccessText'),
      'error' => _t(state, 'system.updateFailedText'),
      _ => _t(state, 'system.starting'),
    };

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withAlpha(70),
        child: Center(
          child: AntdModal(
            width: 420,
            title: Text(_t(state, 'system.updating')),
            showFooter: isDone || isError,
            okText: _t(state, 'common.confirm'),
            cancelText: _t(state, 'common.cancel'),
            onOk: () => setState(() => _updateProgressVisible = false),
            onCancel: () => setState(() => _updateProgressVisible = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isDone && !isError) const AntdSpin(size: 32),
                  if (isDone)
                    const Icon(Icons.check_circle_outline,
                        color: AntdTokens.success, size: 34),
                  if (isError)
                    const Icon(Icons.cancel_outlined,
                        color: AntdTokens.error, size: 34),
                  const SizedBox(height: 16),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isError
                          ? AntdTokens.error
                          : isDone
                              ? AntdTokens.success
                              : AntdTokens.textColor(context),
                    ),
                  ),
                  if (state.serverUpdateError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.serverUpdateError,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AntdTokens.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  Widget _buildBrand(BuildContext context, {required bool isMobile}) {
    final fg =
        AntdTokens.isDark(context) ? Colors.white : const Color(0xFF001529);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.terminal, size: isMobile ? 16 : 18, color: fg),
        if (!isMobile) ...[
          const SizedBox(width: 8),
          Text(
            'TermiScope',
            style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
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
                  _buildBrand(context, isMobile: false),
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
                '${_t(state, 'common.version')}: v${state.backendVersion}',
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'v${state.backendVersion}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AntdTokens.lightTextSecondary,
                  ),
                ),
                if (state.updateAvailable) ...[
                  const SizedBox(width: 8),
                  AntdButton(
                    type: AntdButtonType.primary,
                    size: AntdSize.small,
                    loading: state.updateLoading,
                    onPressed: () => _showUpdateConfirm(state),
                    child: Text(_t(state, 'common.update')),
                  ),
                ],
              ],
            ),
          ),
        AntdButton(
          type: AntdButtonType.link,
          size: AntdSize.small,
          onPressed: () => _toggleLocale(state),
          child: Text(state.locale == 'zh' ? 'EN' : '中文'),
        ),
        AntdButton(
          type: AntdButtonType.defaultType,
          size: AntdSize.small,
          icon: state.themeMode == ThemeMode.dark
              ? Icons.lightbulb_outline
              : Icons.lightbulb,
          onPressed: () => _toggleTheme(state),
          child: isMobile
              ? null
              : Text(_t(
                  state,
                  state.themeMode == ThemeMode.dark
                      ? 'theme.light'
                      : 'theme.dark')),
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

  Widget _buildPageNavigator(int index) {
    return Navigator(
      key: _pageNavigatorKeys[index],
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _pages[index].child,
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

        return Stack(
          children: [
            Scaffold(
              drawer: _buildDrawer(context, state, visibleIndexes),
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(AntdTokens.headerHeight),
                child: AppBar(
                  automaticallyImplyLeading: false,
                  titleSpacing: 0,
                  title: Builder(
                    builder: (appBarContext) => Container(
                      height: AntdTokens.headerHeight,
                      padding: EdgeInsets.symmetric(
                        horizontal: AntdTokens.headerPaddingForWidth(width),
                      ),
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
                          _buildBrand(context, isMobile: isMobile),
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
                    children: List.generate(
                      _pages.length,
                      _buildPageNavigator,
                    ),
                  ),
                ),
              ),
            ),
            _buildUpdateProgressModal(state),
          ],
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
