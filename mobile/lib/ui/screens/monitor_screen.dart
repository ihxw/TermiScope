import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/monitor_provider.dart';
import '../../data/models/monitor_host.dart';
import '../widgets/app_drawer.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'terminal_screen.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  @override
  void initState() {
    super.initState();
    // Connect on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MonitorProvider>(context, listen: false).connect();
    });
  }

  @override
  void dispose() {
    // Disconnect handled by Provider disposal if scoped,
    // but since Provider might live longer or be app-wide, we should disconnect when leaving screen?
    // Based on architecture, if we want real-time only when screen visible:
    // Provider.of<MonitorProvider>(context, listen: false).disconnect();
    // However, keeping it in provider allows background updates if needed.
    // Let's disconnect for now to save bandwidth/battery.
    // Actually, can't easily access context in dispose sometimes.
    // Better to let Provider handle it or use a "Screen" lifecycle wrapper.
    // For now, simple approach:
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.monitor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Reconnect logic
              final provider = Provider.of<MonitorProvider>(
                context,
                listen: false,
              );
              provider.disconnect();
              provider.connect();
            },
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Consumer<MonitorProvider>(
        builder: (context, provider, child) {
          if (!provider.isConnected && provider.hosts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.hosts.isEmpty) {
            return Center(
              child: Text(AppLocalizations.of(context)!.noHostsMonitored),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // 2 columns for phones
              childAspectRatio: 0.8, // Taller cards
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: provider.hosts.length,
            itemBuilder: (context, index) {
              final host = provider.hosts[index];
              return _buildHostCard(context, host);
            },
          );
        },
      ),
    );
  }

  Widget _buildHostCard(BuildContext context, MonitorHost host) {
    bool isOffline =
        (DateTime.now().millisecondsSinceEpoch / 1000 - host.lastUpdated) > 15;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Name
            Row(
              children: [
                Icon(_getOsIcon(host.os), size: 20, color: Colors.blueGrey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    host.hostname,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOffline ? Colors.red : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),

            // Metrics
            _buildMetricRow(
              AppLocalizations.of(context)!.cpu,
              host.cpu,
              Colors.blue,
            ),
            const SizedBox(height: 4),
            _buildMetricRow(
              AppLocalizations.of(context)!.ram,
              _calcPct(host.memUsed, host.memTotal),
              Colors.purple,
            ),
            const SizedBox(height: 4),
            _buildMetricRow(
              AppLocalizations.of(context)!.disk,
              _calcPct(host.diskUsed, host.diskTotal),
              Colors.orange,
            ),

            const Divider(height: 12),

            // Network
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildNetStat(
                  Icons.arrow_downward,
                  host.netRxRate,
                  Colors.green,
                ),
                _buildNetStat(Icons.arrow_upward, host.netTxRate, Colors.blue),
              ],
            ),

            const Spacer(),

            // Action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isOffline
                    ? null
                    : () => _connectTerminal(context, host),
                icon: const Icon(Icons.terminal, size: 16),
                label: Text(AppLocalizations.of(context)!.connect),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: pct / 100,
          backgroundColor: color.withOpacity(0.1),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
        ),
      ],
    );
  }

  Widget _buildNetStat(IconData icon, double bytesPerSec, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 2),
        Text(_formatSpeed(bytesPerSec), style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  void _connectTerminal(BuildContext context, MonitorHost host) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TerminalScreen(hostId: host.hostId, title: host.hostname),
      ),
    );
  }

  IconData _getOsIcon(String os) {
    os = os.toLowerCase();
    if (os.contains('win')) return Icons.window;
    if (os.contains('mac') || os.contains('darwin'))
      return Icons.computer; // No apple icon in standard material
    return Icons.desktop_windows; // Generic linux/desktop
  }

  double _calcPct(double used, double total) {
    if (total == 0) return 0;
    return (used / total) * 100;
  }

  String _formatSpeed(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B/s';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} K/s';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} M/s';
  }
}
