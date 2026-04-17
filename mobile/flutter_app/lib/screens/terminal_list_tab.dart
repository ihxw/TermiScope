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

          return ListView.separated(
            itemCount: state.hosts.length,
            separatorBuilder: (context, index) => const Divider(color: Color(0xFF333333), height: 1),
            itemBuilder: (context, index) {
              final host = state.hosts[index];
              final hostName = host['name'] ?? 'Unnamed';
              final address = host['host'] ?? '';
              final port = host['port'] ?? 22;
              final user = host['username'] ?? 'root';
              final hostId = host['id'];

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                tileColor: const Color(0xFF1E1E1E),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.terminal, color: Color(0xFF64D2FF)),
                ),
                title: Text(
                  hostName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '$user@$address:$port',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TerminalSessionScreen(
                        hostId: hostId,
                        hostName: hostName,
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
