import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/host_provider.dart';
import '../../providers/terminal_provider.dart';
import '../../models/ssh_host.dart';
import 'terminal_screen.dart';

class TerminalListScreen extends StatefulWidget {
  const TerminalListScreen({super.key});

  @override
  State<TerminalListScreen> createState() => _TerminalListScreenState();
}

class _TerminalListScreenState extends State<TerminalListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HostProvider>(context, listen: false).fetchHosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hostProvider = Provider.of<HostProvider>(context);
    final terminalProvider = Provider.of<TerminalProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.terminal),
      ),
      body: hostProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : hostProvider.error != null
              ? Center(child: Text(hostProvider.error!))
              : hostProvider.hosts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.terminal, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noHostsFound,
                            style: const TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noHostsForTerminal,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : _buildHostList(hostProvider, terminalProvider, l10n),
    );
  }

  Widget _buildHostList(HostProvider hostProvider, TerminalProvider terminalProvider, AppLocalizations l10n) {
    return ListView.builder(
      itemCount: hostProvider.hosts.length,
      itemBuilder: (context, index) {
        final host = hostProvider.hosts[index];
        final existingSession = terminalProvider.findSessionByHostId(host.id);
        
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(Icons.computer),
            ),
            title: Text(host.name),
            subtitle: Text('${host.hostname}:${host.port} (${host.username})'),
            trailing: existingSession != null
                ? Chip(
                    label: Text(l10n.connected),
                    backgroundColor: Colors.green.shade100,
                    labelStyle: TextStyle(color: Colors.green.shade800),
                  )
                : null,
            onTap: () => _openTerminal(context, host, terminalProvider),
          ),
        );
      },
    );
  }

  void _openTerminal(BuildContext context, SSHHost host, TerminalProvider terminalProvider) {
    // Add a new terminal session
    final sessionId = terminalProvider.addSession(
      hostId: host.id,
      name: host.name,
    );

    // Navigate to terminal screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TerminalScreen(
          sessionId: sessionId,
          host: host,
        ),
      ),
    );
  }
}