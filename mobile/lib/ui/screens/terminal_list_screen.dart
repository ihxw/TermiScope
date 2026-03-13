import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/terminal_provider.dart';
import '../../providers/host_provider.dart';
import 'terminal_screen.dart';

class TerminalListScreen extends StatefulWidget {
  const TerminalListScreen({super.key});

  @override
  State<TerminalListScreen> createState() => _TerminalListScreenState();
}

class _TerminalListScreenState extends State<TerminalListScreen> {
  int? _selectedHostId;
  bool _recordingEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HostProvider>(context, listen: false).fetchHosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          // 工具栏（紧凑模式，无AppBar标题）
          _buildToolbar(context, l10n, isDark),

          // 终端会话标签 + 内容区
          Expanded(
            child: Consumer<TerminalProvider>(
              builder: (context, terminalProvider, child) {
                if (terminalProvider.sessions.isEmpty) {
                  return _buildEmptyState(context, l10n);
                }
                return _buildTerminalTabs(context, terminalProvider, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建工具栏 - 参照Web端Terminal.vue
  Widget _buildToolbar(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    return Consumer<HostProvider>(
      builder: (context, hostProvider, child) {
        final terminalProvider = Provider.of<TerminalProvider>(
          context,
          listen: false,
        );
        final availableHosts = hostProvider.hosts
            .where((h) => h.hostType != 'monitor_only')
            .toList();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              // 工具栏内容（靠左对齐）
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // 主机选择器
                      Container(
                        width: 140,
                        height: 28,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedHostId,
                            hint: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                l10n.terminalSelectHost,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            isExpanded: true,
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 20),
                            items: availableHosts.map((host) {
                              return DropdownMenuItem<int>(
                                value: host.id,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    host.name,
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (hostId) {
                              if (hostId != null) {
                                final host = availableHosts.firstWhere(
                                  (h) => h.id == hostId,
                                );
                                _handleConnectHost(terminalProvider, host);
                                setState(() => _selectedHostId = null);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 新建主机按钮（蓝色，对齐Web版）
                      SizedBox(
                        height: 28,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            // TODO: 打开新建主机对话框
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.comingSoon)),
                            );
                          },
                          icon: const Icon(Icons.add, size: 14),
                          label: Text(
                            l10n.terminalNewHost,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 快速连接按钮
                      SizedBox(
                        height: 28,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.comingSoon)),
                            );
                          },
                          icon: const Icon(Icons.bolt, size: 14),
                          label: Text(
                            l10n.terminalQuickConnect,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 录制开关
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam,
                              size: 14,
                              color: _recordingEnabled
                                  ? Colors.red
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.terminalRecordSession,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              height: 18,
                              child: Switch(
                                value: _recordingEnabled,
                                onChanged: (val) =>
                                    setState(() => _recordingEnabled = val),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建终端标签页 - 类似浏览器Tab样式
  Widget _buildTerminalTabs(
    BuildContext context,
    TerminalProvider terminalProvider,
    bool isDark,
  ) {
    final activeIndex = terminalProvider.activeSessionId == null
        ? 0
        : terminalProvider.sessions
              .indexWhere((s) => s.id == terminalProvider.activeSessionId)
              .clamp(0, terminalProvider.sessions.length - 1);

    return Column(
      children: [
        // 标签栏 - 模拟浏览器标签
        Container(
          height: 28,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
          ),
          child: Row(
            children: [
              // 标签列表
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: terminalProvider.sessions.asMap().entries.map((
                      entry,
                    ) {
                      final idx = entry.key;
                      final session = entry.value;
                      final isActive = idx == activeIndex;

                      return _buildTab(
                        context,
                        session: session,
                        isActive: isActive,
                        isDark: isDark,
                        onTap: () =>
                            terminalProvider.setActiveSession(session.id),
                        onClose: () =>
                            terminalProvider.removeSession(session.id),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // 添加新标签按钮
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                onPressed: () {
                  // 打开主机选择
                },
                tooltip: 'New Tab',
                splashRadius: 12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),

        // 终端内容区
        Expanded(
          child: IndexedStack(
            index: activeIndex,
            children: terminalProvider.sessions.map((session) {
              return TerminalScreen(
                hostId: session.hostId,
                title: session.name,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 单个标签 - 类似VS Code/浏览器标签样式
  Widget _buildTab(
    BuildContext context, {
    required dynamic session,
    required bool isActive,
    required bool isDark,
    required VoidCallback onTap,
    required VoidCallback onClose,
  }) {
    final bgColor = isActive
        ? (isDark ? const Color(0xFF2D2D2D) : Colors.white)
        : (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200);

    final borderColor = isActive
        ? Theme.of(context).primaryColor
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 2),
            right: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              width: 1,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.record)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            // 标签名称
            Text(
              session.name,
              style: TextStyle(
                fontSize: 13,
                color: isActive
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey.shade500 : Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 8),
            // 关闭按钮
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            l10n.terminalNoActive,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: Text(l10n.terminalConnectToHost),
          ),
        ],
      ),
    );
  }

  void _handleConnectHost(TerminalProvider terminalProvider, host) {
    final existing = terminalProvider.findSessionByHostId(host.id);
    if (existing != null) {
      terminalProvider.setActiveSession(existing.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to existing session for ${host.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      terminalProvider.addSession(
        hostId: host.id,
        name: host.name,
        record: _recordingEnabled,
      );
    }
  }
}
