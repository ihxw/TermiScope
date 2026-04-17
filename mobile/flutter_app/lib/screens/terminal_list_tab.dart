import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'terminal_session_screen.dart';
import '../utils/responsive.dart';

class TerminalListTab extends StatelessWidget {
  const TerminalListTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosts', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AppState>().logout();
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, child) {
          if (state.hosts.isEmpty) {
            return const Center(
              child: Text(
                'No hosts found.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = Responsive.crossAxisCountFromWidth(constraints.maxWidth);

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 100,
                ),
                itemCount: state.hosts.length,
                itemBuilder: (context, index) {
                  final host = state.hosts[index];
                  final hostName = host['name'] ?? 'Unnamed';
                  final address = host['host'] ?? '';
                  final port = host['port'] ?? 22;
                  final user = host['username'] ?? 'root';
                  final hostId = host['id'].toString();

                  final monitorInfo = state.monitorData[hostId] ?? {};
                  final isOnline = monitorInfo.isNotEmpty;

                  IconData icon = Icons.terminal;
                  final hostType = (host['host_type'] ?? '').toString().toLowerCase();
                  if (hostType.contains('windows')) icon = Icons.desktop_windows;
                  else if (hostType.contains('monitor')) icon = Icons.monitor_heart;
                  else if (hostType.contains('sftp')) icon = Icons.folder;

                  return Card(
                    child: InkWell(
                      onTap: () {
                        context.read<AppState>().addTerminal(host);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(icon, color: const Color(0xFF64D2FF), size: 22),
                                  if (isOnline)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(color: const Color(0xFF32D74B), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2D2D2D), width: 1.5)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(hostName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text('$user@$address:$port', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 12)),
                              child: const Text('Connect', style: TextStyle(color: Colors.white)),
                              onPressed: () {
                                context.read<AppState>().addTerminal(host);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
