import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'terminal_session_screen.dart';

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
              int crossAxisCount = 1;
              if (constraints.maxWidth > 900) crossAxisCount = 3;
              else if (constraints.maxWidth > 600) crossAxisCount = 2;

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
                        // Add terminal tab (will activate existing if present)
                        context.read<AppState>().addTerminal(host);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(icon, color: const Color(0xFF64D2FF), size: 28),
                                  if (isOnline)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: const Color(0xFF32D74B), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2D2D2D), width: 2)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(hostName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 6),
                                  Text('$user@$address:$port', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64D2FF)),
                              child: const Text('Connect', style: TextStyle(color: Colors.white)),
                              onPressed: () {
                                // Quick connect / open tab
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
