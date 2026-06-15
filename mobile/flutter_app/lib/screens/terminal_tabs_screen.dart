import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../models/models.dart';
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

  void _quickConnect(AppState state) {
    state.addTerminal(
      Host(id: 0, name: '快速连接', host: 'quick'),
      record: _recordNextSession,
    );
  }

  Widget _buildToolbar(BuildContext context, AppState state) {
    final width = MediaQuery.of(context).size.width;
    final compact = width <= AntdTokens.mobileBreakpoint;
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

    return AntdToolbar(
      bordered: true,
      height: 44,
      leading: [
        SizedBox(
          width: compact ? 200 : 280,
          child: AntdSelect<String>(
            value: selectedHostId,
            placeholder: '选择主机',
            options: hostOptions,
            onChanged: (val) {
              if (val == null) return;
              final host = state.hosts.firstWhere(
                (h) => h.id.toString() == val,
              );
              state.addTerminal(host, record: _recordNextSession);
            },
          ),
        ),
        AntdButton(
          type: AntdButtonType.primary,
          icon: Icons.add,
          onPressed: () => _showAddHostDialog(state),
          child: compact ? null : const Text('新建主机'),
        ),
        AntdButton(
          icon: Icons.flash_on_outlined,
          onPressed: () => _quickConnect(state),
          child: compact ? null : const Text('快速连接'),
        ),
      ],
      trailing: [
        Icon(
          Icons.videocam_outlined,
          size: 16,
          color: _recordNextSession
              ? AntdTokens.error
              : AntdTokens.secondaryTextColor(context),
        ),
        if (!compact)
          Text(
            '录制下次会话',
            style: TextStyle(
              fontSize: AntdTokens.fontSize,
              color: AntdTokens.textColor(context),
            ),
          ),
        AntdSwitch(
          value: _recordNextSession,
          color: AntdTokens.error,
          onChanged: (v) => setState(() => _recordNextSession = v),
        ),
      ],
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
                    : TabBarView(
                        controller: _tabController,
                        physics: const BouncingScrollPhysics(),
                        children: terminals
                            .map((t) => TerminalSessionView(
                                  key: ValueKey(t['tabId']),
                                  hostId: int.parse(t['hostId'].toString()),
                                  record: t['record'] == true,
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
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
              width: 128,
              height: 128,
            ),
            const SizedBox(height: 12),
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
