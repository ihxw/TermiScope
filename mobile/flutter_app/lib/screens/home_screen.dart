import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/monitor_service.dart';
import '../utils/responsive.dart';
import 'monitor_tab.dart';
import 'terminal_tabs_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  MonitorService? _monitorService;
  bool _quickToggle = false;

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'Dashboard',
      'icon': Icons.monitor_heart,
      'widget': const MonitorTab(),
    },
    {
      'title': 'SSH Terminal',
      'icon': Icons.terminal,
      'widget': const TerminalTabsScreen(),
    },
  ];

  @override
  void initState() {
    super.initState();
    // Start websocket for monitor data
    final appState = context.read<AppState>();
    // Fetch initial hosts if empty
    if (appState.hosts.isEmpty) {
      appState.fetchHosts();
    }
    _monitorService = MonitorService(appState);
    _monitorService?.connect();
  }

  @override
  void dispose() {
    _monitorService?.disconnect();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    Navigator.pop(context); // Close the drawer
  }

  Widget _buildHostSelector() {
    return Consumer<AppState>(
      builder: (context, state, child) {
        String? selectedHostId;
        if (state.activeTabId != null) {
          final existing = state.activeTerminals.firstWhere((t) => t['tabId'] == state.activeTabId, orElse: () => {});
          if (existing.isNotEmpty) selectedHostId = existing['hostId'].toString();
        }

        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            hint: const Text('选择主机', style: TextStyle(color: Colors.white70, fontSize: 14)),
            isExpanded: true,
            value: selectedHostId,
            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64D2FF), size: 20),
            items: state.hosts.where((h) => h['host_type'] != 'monitor_only').map((h) {
              return DropdownMenuItem<String>(
                value: h['id'].toString(),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 250),
                  child: Text(
                    '${h['name']} (${h['host']})',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                final host = state.hosts.firstWhere((h) => h['id'].toString() == val);
                state.addTerminal(host);
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Responsive.isMobile(context)
          ? (_currentIndex == 1 ? _buildHostSelector() : Text(_tabs[_currentIndex]['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))
          : Row(
              children: [
                Expanded(child: _buildHostSelector()),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF64D2FF),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(36, 36),
                  ),
                  onPressed: () {
                    final appState = context.read<AppState>();
                    // Quick add: create a quick-connect pseudo-host (id 0)
                    appState.addTerminal({'id': 0, 'name': 'Quick Connect', 'host': 'quick'});
                  },
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.flash_on_outlined, color: Colors.white),
                  onPressed: () {
                    final appState = context.read<AppState>();
                    if (appState.hosts.isNotEmpty) {
                      appState.addTerminal(appState.hosts.first);
                    } else {
                      appState.fetchHosts();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在加载主机列表...')));
                    }
                  },
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                    color: const Color(0xFF2D2D2D),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.screen_share_outlined, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Switch(
                        value: _quickToggle,
                        activeColor: const Color(0xFF64D2FF),
                        onChanged: (v) => setState(() => _quickToggle = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1E1E1E),
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2D2D2D)),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text('TermiScope', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Dashboard', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
            ...List.generate(_tabs.length, (index) {
              final isSelected = index == _currentIndex;
              return ListTile(
                dense: true,
                horizontalTitleGap: 8,
                leading: Icon(_tabs[index]['icon'], size: 20, color: isSelected ? const Color(0xFF64D2FF) : Colors.grey),
                title: Text(
                  _tabs[index]['title'],
                  style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 14),
                ),
                selected: isSelected,
                selectedTileColor: const Color(0xFF2D2D2D), // Web active item color
                onTap: () => _selectTab(index),
              );
            }),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs.map((t) => t['widget'] as Widget).toList(),
      ),
    );
  }
}
