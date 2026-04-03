import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/host_provider.dart';
import '../../providers/terminal_provider.dart';
import '../../models/ssh_host.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'terminal_screen.dart';

class HostListScreen extends StatefulWidget {
  const HostListScreen({super.key});

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HostProvider>(context, listen: false).fetchHosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<HostProvider>(
        builder: (context, hostProvider, child) {
          if (hostProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (hostProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${hostProvider.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                  ElevatedButton(
                    onPressed: () => hostProvider.fetchHosts(),
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            );
          }

          if (hostProvider.hosts.isEmpty) {
            return Center(
              child: Text(AppLocalizations.of(context)!.noHostsFound),
            );
          }

          return RefreshIndicator(
            onRefresh: () => hostProvider.fetchHosts(),
            child: ListView.builder(
              itemCount: hostProvider.hosts.length,
              itemBuilder: (context, index) {
                final host = hostProvider.hosts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey,
                    child: const Icon(Icons.terminal, color: Colors.white),
                  ),
                  title: Text(host.name ?? ''),
                  subtitle: Text('${host.username ?? ''}@${host.hostname ?? ''}:${host.port ?? 22}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final terminalProvider = Provider.of<TerminalProvider>(context, listen: false);
                    final sessionId = terminalProvider.addSession(
                      hostId: host.id,
                      name: host.name ?? 'Host',
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TerminalScreen(
                          sessionId: sessionId,
                          host: host,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
