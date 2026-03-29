import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../../providers/monitor_provider.dart';
import '../../models/monitor_host.dart';

class MonitorDashboardScreen extends StatefulWidget {
  const MonitorDashboardScreen({super.key});

  @override
  State<MonitorDashboardScreen> createState() => _MonitorDashboardScreenState();
}

class _MonitorDashboardScreenState extends State<MonitorDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final monitorProvider = Provider.of<MonitorProvider>(context, listen: false);
      // Initialize monitoring connection
      monitorProvider.connect();
    });
  }

  @override
  void dispose() {
    // Disconnect monitoring when leaving
    Provider.of<MonitorProvider>(context, listen: false).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitorProvider = Provider.of<MonitorProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.monitor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh monitoring
              final provider = Provider.of<MonitorProvider>(context, listen: false);
              provider.disconnect();
              provider.connect();
            },
          ),
        ],
      ),
      body: monitorProvider.hosts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.monitor, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No Monitored Hosts',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You have not added any hosts to monitor yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                final provider = Provider.of<MonitorProvider>(context, listen: false);
                provider.disconnect();
                provider.connect();
              },
              child: ListView.builder(
                itemCount: monitorProvider.hosts.length,
                itemBuilder: (context, index) {
                  final host = monitorProvider.hosts[index];
                  return _buildHostCard(host, l10n);
                },
              ),
            ),
    );
  }

  Widget _buildHostCard(MonitorHost host, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(host.flag),
        ),
        title: Text(host.name.isNotEmpty ? host.name : host.hostname),
        subtitle: Text('${host.hostname} • ${host.os}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMonitorRow(l10n.cpu, '${host.cpu.toStringAsFixed(1)}%', Colors.blue),
                const SizedBox(height: 8),
                _buildMonitorRow('Memory', '${_formatBytes(host.memUsed, 1)} / ${_formatBytes(host.memTotal, 1)}', Colors.green),
                const SizedBox(height: 8),
                _buildMonitorRow(l10n.disk, '${_formatBytes(host.diskUsed, 1)} / ${_formatBytes(host.diskTotal, 1)}', Colors.orange),
                const SizedBox(height: 8),
                _buildMonitorRow('Network', 'RX: ${_formatBytesPerSecond(host.netRxRate)}/s • TX: ${_formatBytesPerSecond(host.netTxRate)}/s', Colors.purple),
                const SizedBox(height: 8),
                _buildMonitorRow(l10n.uptime, _formatUptime(host.uptime), Colors.teal),
                const SizedBox(height: 8),
                _buildMonitorRow('Agent Version', host.agentVersion, Colors.grey),
                const SizedBox(height: 8),
                if (host.netTrafficLimit > 0)
                  _buildMonitorRow('Traffic Limit', '${_formatBytes(host.netMonthlyRx + host.netMonthlyTx, 1)} / ${_formatBytes(host.netTrafficLimit, 1)}', Colors.amber),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitorRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: color)),
      ],
    );
  }

  String _formatBytes(double bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    int digitGroups = (math.log(bytes) / math.log(1024)).floor();
    if (digitGroups > 4) digitGroups = 4;
    return "${(bytes / math.pow(1024, digitGroups)).toStringAsFixed(decimals)} ${units[digitGroups]}";
  }

  String _formatBytesPerSecond(double bytes) {
    return _formatBytes(bytes, 2);
  }

  String _formatUptime(int seconds) {
    int days = seconds ~/ 86400;
    int hours = (seconds % 86400) ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    return "$days d $hours h $minutes m";
  }


}