import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      final oldIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: count,
        vsync: this,
        initialIndex: count > 0 ? (oldIndex < count ? oldIndex : count - 1) : 0,
      );
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
          // When a new terminal is added, usually it's at the end, jump to it
          if (terminals.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
               if(mounted && _tabController != null) {
                  _tabController!.index = terminals.length - 1;
               }
            });
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
                            Text(t['name']),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => state.removeTerminal(t['tabId']),
                              child: const Icon(Icons.close, size: 14),
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
                ? const Center(child: Text('No active terminals. Select a host to connect.', style: TextStyle(color: Colors.grey)))
                : TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(), // Prevent accidental sliding during terminal interaction
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
