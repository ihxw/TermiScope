import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/app_state.dart';
import 'terminal_session_screen.dart';

class TerminalTabsScreen extends StatefulWidget {
  const TerminalTabsScreen({super.key});

  @override
  State<TerminalTabsScreen> createState() => _TerminalTabsScreenState();
}

class _TerminalTabsScreenState extends State<TerminalTabsScreen> with TickerProviderStateMixin {
  TabController? _tabController;
  int _prevTabCount = 0;

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
        if (!_tabController!.indexIsChanging) return;
        final idx = _tabController!.index;
        final terminals = context.read<AppState>().activeTerminals;
        if (idx >= 0 && idx < terminals.length) {
          context.read<AppState>().setActiveTabId(terminals[idx]['tabId']);
        }
      });
    }
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
                   final idx = terminals.indexWhere((t) => t['tabId'] == activeId);
                   if (idx != -1) desired = idx;
                 }
                 _tabController!.index = desired;
               }
            });
          }
        } else {
          // If tabs count unchanged but activeTabId changed, ensure controller reflects it
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

        return Column(
          children: [
            // TabBar matching VS Code / Web style
            if (terminals.isNotEmpty)
               Container(
                 color: const Color(0xFF1E1E1E),
                 width: double.infinity,
                 child: Align(
                   alignment: Alignment.centerLeft,
                   child: TabBar(
                     controller: _tabController,
                     isScrollable: true,
                     indicatorColor: const Color(0xFF64D2FF),
                     labelColor: Colors.white,
                     unselectedLabelColor: Colors.grey,
                     tabAlignment: TabAlignment.start,
                    tabs: terminals.map((t) => Tab(
                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                                Text(t['name'], style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => state.removeTerminal(t['tabId']),
                                  child: const Icon(Icons.close, size: 12),
                                ),
                             ],
                           )
                         )).toList(),
                   ),
                 ),
               ),

            // TabBarView
            Expanded(
              child: terminals.isEmpty
                ? Center(
                    child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              'assets/illustrations/empty_terminal.svg',
                              width: 140,
                              height: 140,
                            ),
                            const SizedBox(height: 18),
                            const Text('没有活动的终端', style: TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 18),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF64D2FF),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                final hosts = context.read<AppState>().hosts.where((h) => h.hostType != 'monitor_only').toList();
                                if (hosts.isEmpty) {
                                  context.read<AppState>().fetchHosts();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到主机，正在刷新...')));
                                  return;
                                }

                                showModalBottomSheet(
                                  context: context,
                                  builder: (ctx) {
                                    return SafeArea(
                                      child: ListView(
                                        children: hosts.map((h) => ListTile(
                                          title: Text(h.name),
                                          subtitle: Text('${h.host}:${h.port}'),
                                          onTap: () {
                                            Navigator.of(ctx).pop();
                                            context.read<AppState>().addTerminal(h);
                                          },
                                        )).toList(),
                                      ),
                                    );
                                  }
                                );
                              },
                              child: const Text('+ 连接到 SSH 主机', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            )
                          ],
                        ),
                  )
                : TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(), // Enable swipe gesture for tab switching
                    children: terminals.map((t) => TerminalSessionView(
                      key: ValueKey(t['tabId']),
                      hostId: int.parse(t['hostId'].toString()), 
                    )).toList(),
                  ),
            ),
          ],
        );
      },
    );
  }
}
