import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/monitor_service.dart';
import '../models/models.dart';
import 'monitor_tab.dart';
import 'terminal_tabs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  MonitorService? _monitorService;

  final List<Widget> _pages = [
    const MonitorTab(),
    const TerminalTabsScreen(),
    const SettingsScreen(),
  ];

  final List<Map<String, dynamic>> _tabLabels = const [
    {'label': 'Dashboard', 'icon': Icons.monitor_heart_outlined, 'activeIcon': Icons.monitor_heart},
    {'label': '终端', 'icon': Icons.terminal_outlined, 'activeIcon': Icons.terminal},
    {'label': '设置', 'icon': Icons.settings_outlined, 'activeIcon': Icons.settings},
  ];

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
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

  Widget _buildTerminalAppBar() {
    return Consumer<AppState>(
      builder: (context, state, child) {
        String? selectedHostId;
        if (state.activeTabId != null) {
          final existing = state.activeTerminals.firstWhere(
            (t) => t['tabId'] == state.activeTabId,
            orElse: () => {},
          );
          if (existing.isNotEmpty) selectedHostId = existing['hostId'].toString();
        }

        return Row(
          children: [
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  hint: const Text('选择主机', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  isExpanded: true,
                  value: selectedHostId,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64D2FF), size: 20),
                  items: state.hosts
                      .where((h) => h.hostType != 'monitor_only')
                      .map((h) => DropdownMenuItem<String>(
                            value: h.id.toString(),
                            child: Text('${h.name} (${h.host})',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final host = state.hosts.firstWhere(
                        (h) => h.id.toString() == val,
                      );
                      state.addTerminal(host);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64D2FF),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                minimumSize: const Size(36, 36),
              ),
              onPressed: () {
                state.addTerminal(Host(id: 0, name: '快速连接', host: 'quick'));
              },
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.flash_on_outlined, color: Colors.white),
              onPressed: () {
                if (state.hosts.isNotEmpty) {
                  state.addTerminal(state.hosts.first);
                } else {
                  state.fetchHosts();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('正在加载主机列表...')));
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _currentIndex == 1
            ? _buildTerminalAppBar()
            : Text(
                _tabLabels[_currentIndex]['label'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: _tabLabels.map((t) {
          return BottomNavigationBarItem(
            icon: Icon(t['icon'] as IconData),
            activeIcon: Icon(t['activeIcon'] as IconData),
            label: t['label'] as String,
          );
        }).toList(),
      ),
    );
  }
}
