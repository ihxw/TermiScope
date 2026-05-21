import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../utils/translation.dart';
import 'host_edit_dialog.dart';

class HostManagementScreen extends StatefulWidget {
  const HostManagementScreen({super.key});

  @override
  State<HostManagementScreen> createState() => _HostManagementScreenState();
}

class _HostManagementScreenState extends State<HostManagementScreen> {
  bool _isLoading = false;

  Future<void> _loadHosts() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    await state.fetchHosts();
    setState(() => _isLoading = false);
  }

  void _showAddHostDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const HostEditDialog(),
    ).then((_) => _loadHosts());
  }

  void _testHost(AppState state, Host host) async {
    final result = await state.testHostConnection(host.id.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? ''),
          backgroundColor: result['success'] == true ? const Color(0xFF2ED573) : Colors.redAccent,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _deployMonitorAgent(AppState state, Host host) async {
    final success = await state.deployMonitorAgent(host.id.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Monitor agent deployed successfully' : 'Deployment failed'),
          backgroundColor: success ? const Color(0xFF2ED573) : Colors.redAccent,
        ),
      );
    }
  }

  void _stopMonitorAgent(AppState state, Host host) async {
    final success = await state.stopMonitorAgent(host.id.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Monitor agent stopped' : 'Failed to stop agent'),
          backgroundColor: success ? const Color(0xFF2ED573) : Colors.redAccent,
        ),
      );
    }
  }

  void _showEditHostDialog(Host host) {
    showDialog(
      context: context,
      builder: (ctx) => HostEditDialog(host: {
        'id': host.id,
        'name': host.name,
        'host': host.host,
        'port': host.port,
        'username': host.username,
        'host_type': host.hostType,
        'monitor_enabled': host.monitorEnabled,
        'net_traffic_limit': host.netTrafficLimit,
        'net_reset_day': host.netResetDay,
        'net_traffic_counter_mode': host.netTrafficCounterMode,
        'net_traffic_used_adjustment': host.netTrafficUsedAdjustment,
        'expiration_date': host.expirationDate,
        'billing_amount': host.billingAmount,
        'billing_period': host.billingPeriod,
        'currency': host.currency,
        'sort_order': host.sortOrder,
      }),
    ).then((_) => _loadHosts());
  }

  void _confirmDeleteHost(AppState state, Host host) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translation.getText(state.locale, 'common.confirmDelete')),
        content: Text('${host.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translation.getText(state.locale, 'common.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await state.deleteHost(host.id.toString());
              _loadHosts();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(Translation.getText(state.locale, 'common.confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddHostDialog,
        backgroundColor: const Color(0xFFFF5C35),
        mini: true,
        child: const Icon(Icons.add, color: Colors.black87),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Translation.getText(state.locale, 'nav.hosts'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadHosts,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.hosts.isEmpty
                    ? Center(
                        child: Text(
                          Translation.getText(state.locale, 'sftp.emptyFolder'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: state.hosts.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (ctx, idx) {
                          final host = state.hosts[idx];
                          final isMonitorOnly = host.hostType == 'monitor_only';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isMonitorOnly
                                    ? const Color(0xFF2ED573).withOpacity(0.2)
                                    : const Color(0xFFFF5C35).withOpacity(0.2),
                                child: Icon(
                                  isMonitorOnly ? Icons.monitor_heart : Icons.terminal,
                                  color: isMonitorOnly ? const Color(0xFF2ED573) : const Color(0xFFFF5C35),
                                  size: 18,
                                ),
                              ),
                              title: Text(host.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${host.host}:${host.port}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isMonitorOnly)
                                    IconButton(
                                      icon: const Icon(Icons.wifi_find, color: Color(0xFFFF5C35), size: 20),
                                      tooltip: 'Test Connection',
                                      onPressed: () => _testHost(state, host),
                                    ),
                                  if (host.monitorEnabled) ...[
                                    IconButton(
                                      icon: const Icon(Icons.arrow_circle_down_outlined, color: Color(0xFF2ED573), size: 20),
                                      tooltip: 'Deploy Monitor Agent',
                                      onPressed: () => _deployMonitorAgent(state, host),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.orangeAccent, size: 20),
                                      tooltip: 'Stop Monitor Agent',
                                      onPressed: () => _stopMonitorAgent(state, host),
                                    ),
                                  ],
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _showEditHostDialog(host),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                    onPressed: () => _confirmDeleteHost(state, host),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
