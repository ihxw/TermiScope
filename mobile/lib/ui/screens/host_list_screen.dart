import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/host_provider.dart';
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
                    backgroundColor: host.status == 'online'
                        ? Colors.green
                        : Colors.grey,
                    child: const Icon(Icons.terminal, color: Colors.white),
                  ),
                  title: Text(host.name),
                  subtitle: Text('${host.username}@${host.host}:${host.port}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            TerminalScreen(hostId: host.id, title: host.name),
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
