import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/host_provider.dart';
import '../../providers/terminal_provider.dart';
import '../../models/ssh_host.dart';
import 'terminal_screen.dart';

class HostManagementScreen extends StatefulWidget {
  const HostManagementScreen({super.key});

  @override
  State<HostManagementScreen> createState() => _HostManagementScreenState();
}

class _HostManagementScreenState extends State<HostManagementScreen> {
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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.hosts),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditHostDialog(context, null),
          ),
        ],
      ),
      body: hostProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : hostProvider.error != null
              ? Center(child: Text(hostProvider.error!))
              : _buildHostList(hostProvider, l10n),
    );
  }

  Widget _buildHostList(HostProvider hostProvider, AppLocalizations l10n) {
    if (hostProvider.hosts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.computer, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l10n.noHostsFound,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _showAddEditHostDialog(context, null),
              child: Text(l10n.addHost),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => hostProvider.fetchHosts(),
      child: ListView.builder(
        itemCount: hostProvider.hosts.length,
        itemBuilder: (context, index) {
          final host = hostProvider.hosts[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(Icons.computer),
              ),
              title: Text(host.name),
              subtitle: Text('${host.hostname}:${host.port} (${host.username})'),
              trailing: PopupMenuButton(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _showAddEditHostDialog(context, host);
                      break;
                    case 'delete':
                      _confirmDeleteHost(context, host);
                      break;
                    case 'test':
                      _testConnection(context, host);
                      break;
                    case 'deploy':
                      _deployMonitor(context, host);
                      break;
                    case 'stop':
                      _stopMonitor(context, host);
                      break;
                    case 'connect':
                      final terminalProvider = Provider.of<TerminalProvider>(context, listen: false);
                      final sessionId = terminalProvider.addSession(
                        hostId: host.id,
                        name: host.name,
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
                      break;
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit, size: 18),
                        const SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 18),
                        const SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'test',
                    child: Row(
                      children: [
                        const Icon(Icons.network_check, size: 18),
                        const SizedBox(width: 8),
                        Text('Test Connection'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'connect',
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 18),
                        const SizedBox(width: 8),
                        Text('Connect SSH'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'deploy',
                    child: Row(
                      children: [
                        const Icon(Icons.rocket_launch, size: 18),
                        const SizedBox(width: 8),
                        Text('Deploy Monitor'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'stop',
                    child: Row(
                      children: [
                        const Icon(Icons.stop, size: 18),
                        const SizedBox(width: 8),
                        Text('Stop Monitor'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddEditHostDialog(BuildContext context, SSHHost? host) async {
    final hostProvider = Provider.of<HostProvider>(context, listen: false);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: host?.name);
    final hostnameController = TextEditingController(text: host?.hostname);
    final portController = TextEditingController(text: host?.port.toString());
    final usernameController = TextEditingController(text: host?.username);
    final passwordController = TextEditingController(text: host?.password);
    final privateKeyController = TextEditingController(text: host?.privateKey);
    final passphraseController = TextEditingController(text: host?.passphrase);

    bool isEditing = host != null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Host' : 'Add Host'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: hostnameController,
                    decoration: const InputDecoration(labelText: 'Hostname/IP *'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter hostname or IP';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: portController,
                    decoration: const InputDecoration(labelText: 'Port *'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter port';
                      }
                      final port = int.tryParse(value);
                      if (port == null || port < 1 || port > 65535) {
                        return 'Please enter a valid port (1-65535)';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username *'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter username';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  TextFormField(
                    controller: privateKeyController,
                    decoration: const InputDecoration(labelText: 'Private Key'),
                    maxLines: 3,
                  ),
                  TextFormField(
                    controller: passphraseController,
                    decoration: const InputDecoration(labelText: 'Passphrase'),
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final newHost = SSHHost(
                  id: host?.id ?? 0,
                  name: nameController.text.trim(),
                  hostname: hostnameController.text.trim(),
                  port: int.parse(portController.text),
                  username: usernameController.text.trim(),
                  password: passwordController.text.isEmpty ? null : passwordController.text,
                  privateKey: privateKeyController.text.isEmpty ? null : privateKeyController.text,
                  passphrase: passphraseController.text.isEmpty ? null : passphraseController.text,
                  fingerprint: host?.fingerprint,
                  isActive: host?.isActive ?? true,
                  createdAt: host?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                if (isEditing) {
                  await hostProvider.updateHost(newHost);
                } else {
                  await hostProvider.addHost(newHost);
                }

                if (mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteHost(BuildContext context, SSHHost host) async {
    final hostProvider = Provider.of<HostProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text('Are you sure you want to delete "${host.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              await hostProvider.deleteHost(host.id);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection(BuildContext context, SSHHost host) async {
    final hostProvider = Provider.of<HostProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    await hostProvider.testConnection(host.id);
    if (hostProvider.error == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection to ${host.name} successful!')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection to ${host.name} failed: ${hostProvider.error}')),
        );
      }
    }
  }

  Future<void> _deployMonitor(BuildContext context, SSHHost host) async {
    final hostProvider = Provider.of<HostProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    await hostProvider.deployMonitor(host.id);
    if (hostProvider.error == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Monitor deployed to ${host.name}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to deploy monitor to ${host.name}: ${hostProvider.error}')),
        );
      }
    }
  }

  Future<void> _stopMonitor(BuildContext context, SSHHost host) async {
    final hostProvider = Provider.of<HostProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    await hostProvider.stopMonitor(host.id);
    if (hostProvider.error == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Monitor stopped on ${host.name}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop monitor on ${host.name}: ${hostProvider.error}')),
        );
      }
    }
  }
}