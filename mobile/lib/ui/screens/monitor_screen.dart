import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/monitor_provider.dart';
import '../../models/monitor_host.dart';
import '../utils/monitor_utils.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'terminal_screen.dart';


import 'package:intl/intl.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  bool _isCardView = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MonitorProvider>(context, listen: false).connect();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Consumer<MonitorProvider>(
        builder: (context, provider, child) {
          if (!provider.isConnected && provider.hosts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.hosts.isEmpty) {
            return Center(child: Text(l10n.noHostsMonitored));
          }

          final total = provider.hosts.length;
          final online = provider.hosts
              .where(
                (h) =>
                    (DateTime.now().millisecondsSinceEpoch ~/ 1000 - double.parse(h.lastUpdated.toString())) <=
                    15,
              )
              .length;

          return Column(
            children: [
              // Header with stats and toggle
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ToggleButtons(
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        isSelected: [_isCardView, !_isCardView],
                        onPressed: (index) {
                          setState(() {
                            _isCardView = index == 0;
                          });
                        },
                        fillColor: Colors.blue,
                        selectedColor: Colors.white,
                        color: Colors.white70,
                        renderBorder: false,
                        children: const [
                          Icon(Icons.grid_view, size: 20),
                          Icon(Icons.view_list, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${l10n.monitorTotal}: $total',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${l10n.monitorOnline}: $online',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isCardView
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // Adaptive grid logic
                          int crossAxisCount = 1;
                          if (width >= 1200) {
                            crossAxisCount = 3;
                          } else if (width >= 600)
                            crossAxisCount = 2;

                          return GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              mainAxisExtent:
                                  310, // Fixed height for cards to encompass all info
                            ),
                            itemCount: provider.hosts.length,
                            itemBuilder: (context, index) {
                              return _MonitorHostCard(
                                host: provider.hosts[index],
                              );
                            },
                          );
                        },
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: provider.hosts.length,
                        separatorBuilder: (ctx, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _MonitorHostListItem(
                            host: provider.hosts[index],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonitorHostListItem extends StatelessWidget {
  final MonitorHost host;

  const _MonitorHostListItem({required this.host});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<MonitorProvider>(context, listen: false);
    final isOffline =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - double.parse(host.lastUpdated.toString())) > 15;
    final flagColor = MonitorUtils.getFlagColor(host.flag);
    final isMonitorOnly = provider.getHostType(host.hostId) == 'monitor_only';

    final displayName = host.name.isNotEmpty ? host.name : host.hostname;
    final subName = host.name.isNotEmpty ? host.hostname : '';

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          border: Border(
            left: host.flag.isNotEmpty
                ? BorderSide(color: flagColor, width: 4.0)
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Icon
            Icon(
              MonitorUtils.getOsIcon(host.os),
              size: 20,
              color: Colors.blueGrey,
            ),
            const SizedBox(width: 8),

            // Name & IP
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subName.isNotEmpty)
                    Text(
                      subName,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (isOffline)
                    Text(
                      'OFFLINE',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),

            // Tiny Metrics
            Expanded(
              flex: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMiniMetric('CPU', host.cpu, Colors.blue),
                  _buildMiniMetric(
                    'RAM',
                    (host.memUsed /
                        (host.memTotal > 0 ? host.memTotal : 1) *
                        100),
                    Colors.purple,
                  ),
                  _buildMiniMetric(
                    'Disk',
                    (host.diskUsed /
                        (host.diskTotal > 0 ? host.diskTotal : 1) *
                        100),
                    Colors.orange,
                  ),
                ],
              ),
            ),

            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.terminal, size: 16),
                  tooltip: isMonitorOnly ? l10n.monitorOnly : l10n.connect,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: (isOffline || isMonitorOnly)
                      ? null
                      : () => _connectTerminal(context),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.history, size: 16),
                  tooltip: l10n.history,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showHistoryDialog(context, host.hostId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, double val, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 2),
        SizedBox(
          width: 30,
          height: 3,
          child: LinearProgressIndicator(
            value: val / 100,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  void _connectTerminal(BuildContext context) {
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => TerminalScreen(
    //       hostId: host.hostId,
    //       initialTitle: host.name.isNotEmpty ? host.name : host.hostname,
    //     ),
    //   ),
    // );
    
    // Show a message that terminal connection is not available from monitor screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminal Connection'),
        content: const Text('Terminal connection is not available from monitor screen. Please use the Hosts screen to connect to a terminal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, int hostId) {
    showDialog(
      context: context,
      builder: (context) => _HistoryDialog(hostId: hostId),
    );
  }
}

class _MonitorHostCard extends StatelessWidget {
  final MonitorHost host;

  const _MonitorHostCard({required this.host});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isOffline =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - double.parse(host.lastUpdated.toString())) > 15;
    final flagColor = MonitorUtils.getFlagColor(host.flag);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: host.flag.isNotEmpty
                ? BorderSide(color: flagColor, width: 5)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context, isOffline, l10n),
              const SizedBox(height: 8),

              // Basic Info Line
              _buildInfoLine(context, l10n),
              const SizedBox(height: 12),

              // Metrics
              // CPU
              _buildProgressMetric(
                label: l10n.cpu,
                percent: host.cpu,
                detail:
                    '${host.cpuCount}C ${host.cpuModel.isNotEmpty ? host.cpuModel : ''}',
                valueText: '${host.cpu.toStringAsFixed(2)}%',
              ),
              const SizedBox(height: 8),

              // RAM
              _buildProgressMetric(
                label: l10n.ram,
                percent: _calcPct(host.memUsed, host.memTotal),
                detail:
                    '${MonitorUtils.formatBytes(host.memUsed)} / ${MonitorUtils.formatBytes(host.memTotal)}',
                valueText: '${_calcPct(host.memUsed, host.memTotal).round()}%',
              ),
              const SizedBox(height: 8),

              // Disk
              _buildProgressMetric(
                label: l10n.disk,
                percent: _calcPct(host.diskUsed, host.diskTotal),
                detail:
                    '${MonitorUtils.formatBytes(host.diskUsed)} / ${MonitorUtils.formatBytes(host.diskTotal)}',
                valueText:
                    '${_calcPct(host.diskUsed, host.diskTotal).round()}%',
              ),
              const SizedBox(height: 8),

              // Network
              Row(
                children: [
                  Expanded(
                    child: _buildNetItem(
                      Icons.arrow_downward,
                      Colors.green,
                      host.netRxRate,
                      host.netMonthlyRx,
                      l10n,
                    ),
                  ),
                  Expanded(
                    child: _buildNetItem(
                      Icons.arrow_upward,
                      Colors.blue,
                      host.netTxRate,
                      host.netMonthlyTx,
                      l10n,
                    ),
                  ),
                ],
              ),

              // Traffic Usage (if limit > 0)
              if (host.netTrafficLimit > 0) ...[
                const Divider(height: 16),
                _buildTrafficUsage(context, l10n),
              ],

              const Spacer(),

              // Financial Info (if exists)
              if ((host.expirationDate?.isNotEmpty == true) || host.billingAmount > 0) ...[
                Container(
                  height: 1,
                  color: Colors.grey.shade200,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                ),
                _buildFinancialInfo(context, l10n),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isOffline,
    AppLocalizations l10n,
  ) {
    final provider = Provider.of<MonitorProvider>(context, listen: false);
    final isMonitorOnly = provider.getHostType(host.hostId) == 'monitor_only';
    final displayName = host.name.isNotEmpty ? host.name : host.hostname;
    final subName = host.name.isNotEmpty ? '(${host.hostname})' : '';

    return Row(
      children: [
        Icon(MonitorUtils.getOsIcon(host.os), size: 22, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subName.isNotEmpty)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Text(
                          subName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
              if (isOffline)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    'OFFLINE',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Actions
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Connect
            IconButton(
              icon: const Icon(Icons.terminal, size: 18),
              tooltip: isMonitorOnly ? l10n.monitorOnly : l10n.connect,
              onPressed: (isOffline || isMonitorOnly)
                  ? null
                  : () => _connectTerminal(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20,
            ),
            const SizedBox(width: 8),
            // History
            IconButton(
              icon: const Icon(Icons.history, size: 18),
              tooltip: l10n.history,
              onPressed: () => _showHistoryDialog(context, host.hostId),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoLine(BuildContext context, AppLocalizations l10n) {
    final parts = <String>[];
    if (host.os.isNotEmpty) parts.add(host.os);
    parts.add('${l10n.uptime}: ${MonitorUtils.formatUptime(host.uptime)}');
    if (host.agentVersion.isNotEmpty) parts.add('v${host.agentVersion}');

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: parts
          .map(
            (e) => Text(
              e,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          )
          .toList(),
    );
  }

  Widget _buildProgressMetric({
    required String label,
    required double percent,
    required String detail,
    required String valueText,
  }) {
    final statusColor = MonitorUtils.getStatusColor(percent);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  if (detail.isNotEmpty)
                    Expanded(
                      child: Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Text(valueText, style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
      ],
    );
  }

  Widget _buildNetItem(
    IconData icon,
    Color color,
    double rate,
    double monthly,
    AppLocalizations l10n,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              MonitorUtils.formatSpeed(rate),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Text(
          '${l10n.monitorTotal}: ${MonitorUtils.formatBytes(monthly)}',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildTrafficUsage(BuildContext context, AppLocalizations l10n) {
    final pct = MonitorUtils.getTrafficUsagePct(
      host.netTrafficLimit,
      host.netTrafficCounterMode,
      host.netMonthlyRx,
      host.netMonthlyTx,
      host.netTrafficUsedAdjustment,
    );
    final statusColor = MonitorUtils.getStatusColor(pct.toDouble());

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${l10n.networkUsage} ($pct%)',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              MonitorUtils.formatTrafficUsage(
                host.netTrafficLimit,
                host.netTrafficCounterMode,
                host.netMonthlyRx,
                host.netMonthlyTx,
                host.netTrafficUsedAdjustment,
              ),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 4,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialInfo(BuildContext context, AppLocalizations l10n) {
    final days = MonitorUtils.getDaysUntilExpiration(host.expirationDate);
    Color? dayColor;
    if (days < 0) {
      dayColor = Colors.red;
    } else if (days <= 7) {
      dayColor = Colors.orange;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (host.expirationDate?.isNotEmpty == true)
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  l10n.expirationDate,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(width: 2),
                Text(
                  '${host.expirationDate} ($days)', // simplified
                  style: TextStyle(
                    fontSize: 10,
                    color: dayColor ?? Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

        if (host.billingAmount > 0)
          Expanded(
            child: Text(
              '\${MonitorUtils.formatBillingPeriod(context, host.billingPeriod ?? "")}: \${MonitorUtils.getCurrencySymbol(host.currency ?? "")}\${host.billingAmount}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  void _connectTerminal(BuildContext context) {
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => TerminalScreen(
    //       hostId: host.hostId,
    //       initialTitle: host.name.isNotEmpty ? host.name : host.hostname,
    //     ),
    //   ),
    // );
    
    // Show a message that terminal connection is not available from monitor screen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terminal Connection'),
        content: const Text('Terminal connection is not available from monitor screen. Please use the Hosts screen to connect to a terminal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, int hostId) {
    showDialog(
      context: context,
      builder: (context) => _HistoryDialog(hostId: hostId),
    );
  }

  double _calcPct(double used, double total) {
    if (total == 0) return 0;
    return (used / total) * 100;
  }
}

class _HistoryDialog extends StatefulWidget {
  final int hostId;
  const _HistoryDialog({required this.hostId});

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  bool _loading = true;
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      // final apiService = Provider.of<ApiService>(context, listen: false);
      // final logService = LogService(apiService);
      // final res = await logService.getMonitorLogs(widget.hostId, 1, 20);
      final res = {'data': []}; // Placeholder for now
      if (mounted) {
        setState(() {
          _logs = res['data'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.monitorHistory),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
            ? Center(child: Text(l10n.noHostsFound)) // Use generic empty text
            : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  final status = log['status'] ?? 'unknown';
                  final time = log['created_at'] ?? '';
                  DateTime? date;
                  if (time.isNotEmpty) date = DateTime.tryParse(time);

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: status == 'online' ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      date != null
                          ? DateFormat(
                              'yyyy-MM-dd HH:mm:ss',
                            ).format(date.toLocal())
                          : time,
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel), // or 'Close' if available
        ),
      ],
    );
  }
}
