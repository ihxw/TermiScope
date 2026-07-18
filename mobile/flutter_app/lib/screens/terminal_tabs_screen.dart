import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';
import 'host_edit_dialog.dart';
import 'terminal_session_screen.dart';

class TerminalTabsScreen extends StatefulWidget {
  const TerminalTabsScreen({super.key});

  @override
  State<TerminalTabsScreen> createState() => _TerminalTabsScreenState();
}

class _TerminalTabsScreenState extends State<TerminalTabsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _prevTabCount = 0;
  bool _recordNextSession = false;

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _updateTabController(int count) {
    if (_tabController == null || _tabController!.length != count) {
      _tabController?.dispose();
      _tabController = TabController(
        length: count,
        vsync: this,
        initialIndex: 0,
      );
      _tabController!.addListener(() {
        final idx = _tabController!.index;
        final terminals = context.read<AppState>().activeTerminals;
        if (idx >= 0 && idx < terminals.length) {
          context.read<AppState>().setActiveTabId(terminals[idx]['tabId']);
        }
      });
    }
  }

  Future<void> _showAddHostDialog(AppState state) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const HostEditDialog(),
    );
    if (saved == true && mounted) {
      state.fetchHosts();
    }
  }

  Future<void> _quickConnect(AppState state) async {
    final beforeIds = state.hosts.map((h) => h.id).toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const HostEditDialog(
        title: '快速连接',
        okText: '连接',
        initialValues: {
          'name': '快速连接会话',
          'host': '',
          'port': 22,
          'username': 'root',
          'auth_type': 'password',
          'group_name': '临时连接',
          'description': '一次性连接',
          'host_type': 'control_monitor',
          'remote_shell': 'default',
          'os_type': 'linux',
        },
      ),
    );
    if (saved == true && mounted) {
      await state.fetchHosts();
      final created =
          state.hosts.where((host) => !beforeIds.contains(host.id)).toList();
      if (created.isNotEmpty) {
        state.addTerminal(created.last, record: _recordNextSession);
      }
    }
  }

  Widget _buildToolbar(BuildContext context, AppState state) {
    final width = MediaQuery.of(context).size.width;
    final compact = width <= AntdTokens.mobileBreakpoint;
    final gap = compact ? 6.0 : 8.0;
    final sshHosts =
        state.hosts.where((h) => h.hostType != 'monitor_only').toList();

    String? selectedHostId;
    if (state.activeTabId != null) {
      final existing = state.activeTerminals.firstWhere(
        (t) => t['tabId'] == state.activeTabId,
        orElse: () => {},
      );
      if (existing.isNotEmpty) selectedHostId = existing['hostId'].toString();
    }

    final hostOptions = sshHosts
        .map((h) => AntdSelectOption<String>(
              value: h.id.toString(),
              label: '${h.name} (${h.host}:${h.port})',
              icon: Icons.storage_outlined,
            ))
        .toList();

    return Container(
      height: 38,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AntdTokens.containerColor(context),
        border: Border(
          bottom: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 180 : 280,
              child: AntdSelect<String>(
                value: selectedHostId,
                placeholder: '选择主机',
                options: hostOptions,
                size: AntdSize.small,
                onChanged: (val) {
                  if (val == null) return;
                  final host = state.hosts.firstWhere(
                    (h) => h.id.toString() == val,
                  );
                  state.addTerminal(host, record: _recordNextSession);
                },
              ),
            ),
            SizedBox(width: gap),
            AntdButton(
              type: AntdButtonType.primary,
              size: AntdSize.small,
              icon: Icons.add,
              onPressed: () => _showAddHostDialog(state),
              child: compact ? null : const Text('新建主机'),
            ),
            SizedBox(width: gap),
            AntdButton(
              size: AntdSize.small,
              icon: Icons.flash_on_outlined,
              onPressed: () => _quickConnect(state),
              child: compact ? null : const Text('快速连接'),
            ),
            if (!compact) ...[
              SizedBox(width: gap),
              Container(
                width: 1,
                height: 20,
                color: AntdTokens.borderColor(context),
              ),
            ],
            SizedBox(width: gap),
            Container(
              height: 24,
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
              decoration: BoxDecoration(
                color: AntdTokens.isDark(context)
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x08000000),
                border: Border.all(color: AntdTokens.borderColor(context)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_outlined,
                    size: 16,
                    color: _recordNextSession
                        ? AntdTokens.error
                        : AntdTokens.secondaryTextColor(context),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      '录制下次会话',
                      style: TextStyle(
                        fontSize: 12,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  AntdSwitch(
                    value: _recordNextSession,
                    color: AntdTokens.error,
                    size: AntdSwitchSize.small,
                    onChanged: (v) => setState(() => _recordNextSession = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final terminals = state.activeTerminals;
        if (_prevTabCount != terminals.length) {
          _updateTabController(terminals.length);
          _prevTabCount = terminals.length;
          if (terminals.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tabController != null) {
                final activeId = context.read<AppState>().activeTabId;
                int desired = terminals.length - 1;
                if (activeId != null) {
                  final idx =
                      terminals.indexWhere((t) => t['tabId'] == activeId);
                  if (idx != -1) desired = idx;
                }
                _tabController!.index = desired;
              }
            });
          }
        } else {
          // tabs 数量未变但 activeTabId 变了，同步控制器
          final activeId = context.read<AppState>().activeTabId;
          if (activeId != null && _tabController != null) {
            final idx = terminals.indexWhere((t) => t['tabId'] == activeId);
            if (idx != -1 && _tabController!.index != idx) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _tabController!.index = idx;
              });
            }
          }
        }

        final tabItems = terminals
            .map((t) => AntdTabsItem(
                  key: t['tabId'].toString(),
                  label: Text(t['name']?.toString() ?? ''),
                  closable: true,
                  recording: t['record'] == true,
                ))
            .toList();

        return Container(
          decoration: BoxDecoration(
            color: AntdTokens.containerColor(context),
            borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
            border: Border.all(
              color: AntdTokens.borderSecondaryColor(context),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildToolbar(context, state),
              if (terminals.isNotEmpty)
                AntdTabs(
                  editor: true,
                  items: tabItems,
                  activeKey: state.activeTabId?.toString(),
                  onChange: (key) {
                    final idx = terminals
                        .indexWhere((t) => t['tabId'].toString() == key);
                    if (idx == -1) return;
                    state.setActiveTabId(terminals[idx]['tabId']);
                    _tabController?.animateTo(idx);
                  },
                  onClose: (key) {
                    final term = terminals.firstWhere(
                      (t) => t['tabId'].toString() == key,
                      orElse: () => {},
                    );
                    if (term.isNotEmpty) state.removeTerminal(term['tabId']);
                  },
                ),
              Expanded(
                child: terminals.isEmpty
                    ? _buildEmpty(context, state)
                    : _buildActiveTerminal(terminals, state.activeTabId),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTerminal(
    List<Map<String, dynamic>> terminals,
    String? activeTabId,
  ) {
    final index = _activeTerminalIndex(terminals, activeTabId);
    final terminal = terminals[index];
    return TerminalSessionView(
      key: ValueKey(terminal['tabId']),
      hostId: int.parse(terminal['hostId'].toString()),
      hostLabel: terminal['name']?.toString() ?? '',
      record: terminal['record'] == true,
    );
  }

  int _activeTerminalIndex(
    List<Map<String, dynamic>> terminals,
    String? activeTabId,
  ) {
    if (terminals.isEmpty) return 0;
    final idx = terminals.indexWhere((t) => t['tabId'] == activeTabId);
    return idx == -1 ? 0 : idx;
  }

  Widget _buildEmpty(BuildContext context, AppState state) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/illustrations/empty_terminal.svg',
              width: 184,
              height: 88,
              fit: BoxFit.fill,
            ),
            const SizedBox(height: 4),
            Text(
              '没有活动的终端',
              style: TextStyle(
                color: AntdTokens.secondaryTextColor(context),
                fontSize: AntdTokens.fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            AntdButton(
              type: AntdButtonType.primary,
              onPressed: () => _quickConnect(state),
              child: const Text('连接到 SSH 主机'),
            ),
          ],
        ),
      ),
    );
  }
}
