import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../utils/responsive.dart';
import '../widgets/antd/index.dart';

class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key});
  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  bool _cardMode = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final hosts = state.hosts.where((h) => h.monitorEnabled).toList();
        final onlineCount = hosts.where((h) {
          final hid = h.id.toString();
          return state.monitorData.containsKey(hid) &&
              state.monitorData[hid].isNotEmpty;
        }).length;

        return Column(children: [
          AntdToolbar(height: 44, bordered: true, leading: [
            SizedBox(width: 160, child: AntdSegmented<String>(
              value: _cardMode ? 'card' : 'list',
              options: const {'card': '\u5361\u7247', 'list': '\u5217\u8868'},
              onChanged: (v) => setState(() => _cardMode = v == 'card'),
            )),
          ], trailing: [
            const Icon(Icons.app_registration, size: 14), const SizedBox(width: 4),
            Text('\u603b\u8ba1: ${hosts.length}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(width: 8),
            Text('\u5728\u7ebf: $onlineCount',
                style: const TextStyle(color: AntdTokens.success, fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
          Expanded(child: hosts.isEmpty
            ? const AntdEmpty(description: '\u6682\u65e0\u76d1\u63a7\u4e3b\u673a')
            : _cardMode
                ? _buildCardGrid(context, state, hosts)
                : _buildListView(context, state, hosts)),
        ]);
      },
    );
  }

  Widget _buildCardGrid(BuildContext ctx, AppState state, List hosts) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final cols = Responsive.crossAxisCountFromWidth(constraints.maxWidth);
      return GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols, mainAxisSpacing: 4, crossAxisSpacing: 4,
          mainAxisExtent: _cardMode ? 340 : 280,
        ),
        itemCount: hosts.length,
        itemBuilder: (_, i) => _buildMonitorCard(ctx, state, hosts[i]),
      );
    });
  }

  Widget _buildListView(BuildContext ctx, AppState state, List hosts) {
    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: hosts.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _buildMonitorCard(ctx, state, hosts[i]),
      ),
    );
  }

  Widget _buildMonitorCard(BuildContext ctx, AppState state, var host) {
    final hostId = host.id.toString();
    final info = state.monitorData[hostId] ?? {};
    final isOnline = info.isNotEmpty;

    final cpu = (info['cpu'] ?? 0).toDouble();
    final memUsed = (info['mem_used'] ?? 0).toDouble();
    final memTotal = (info['mem_total'] ?? 1).toDouble();
    final memPct = memTotal > 0 ? (memUsed / memTotal) * 100 : 0.0;
    final os = info['os'] ?? 'Unknown';
    final uptime = info['uptime'] ?? 0;

    double diskUsed = 0, diskTotal = 0;
    if (info['disks'] != null && (info['disks'] as List).isNotEmpty) {
      for (var d in (info['disks'] as List)) {
        diskUsed += (d['used'] ?? 0).toDouble();
        diskTotal += (d['total'] ?? 0).toDouble();
      }
    } else {
      diskUsed = (info['disk_used'] ?? 0).toDouble();
      diskTotal = (info['disk_total'] ?? 1).toDouble();
    }
    final diskPct = diskTotal > 0 ? (diskUsed / diskTotal) * 100 : 0.0;

    final rxRate = (info['net_rx_rate'] ?? 0).toDouble();
    final txRate = (info['net_tx_rate'] ?? 0).toDouble();
    final rxTotal = (info['net_monthly_rx'] ?? 0).toDouble();
    final txTotal = (info['net_monthly_tx'] ?? 0).toDouble();

    final limit = (host.netTrafficLimit ?? 0).toDouble();
    final mode = host.netTrafficCounterMode;
    double measured = 0;
    if (mode == 'rx') { measured = rxTotal; }
    else if (mode == 'tx') { measured = txTotal; }
    else { measured = rxTotal + txTotal; }
    final trafficUsed = measured + host.netTrafficUsedAdjustment;
    final trafficPct = limit > 0
        ? (trafficUsed / limit * 100).clamp(0, 100).toDouble()
        : 0.0;

    final expDate = host.expirationDate;
    final billingAmt = host.billingAmount;
    final billingPrd = host.billingPeriod;
    final currency = host.currency;
    final daysLeft = expDate != null ? _getDaysUntil(expDate) : 0;
    final remainingVal = (expDate != null && billingAmt > 0 && billingPrd != null && billingPrd.isNotEmpty)
        ? _calculateRemainingValue(expDate, billingPrd, billingAmt)
        : '0.00';

    final metricBody = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // OS + uptime
      Row(children: [
        Icon(Icons.desktop_windows, size: 12, color: AntdTokens.secondaryTextColor(ctx)),
        const SizedBox(width: 4),
        Text(os, style: TextStyle(fontSize: 11, color: AntdTokens.secondaryTextColor(ctx))),
        const SizedBox(width: 8),
        Icon(Icons.access_time, size: 12, color: AntdTokens.secondaryTextColor(ctx)),
        const SizedBox(width: 4),
        Text(_formatUptime(uptime), style: TextStyle(fontSize: 11, color: AntdTokens.secondaryTextColor(ctx))),
      ]),
      const SizedBox(height: 8),
      // CPU
      Row(children: [
        SizedBox(width: 32, child: Text('CPU', style: const TextStyle(fontSize: 11))),
        Expanded(child: AntdProgress(percent: cpu, color: AntdTokens.primary, strokeWidth: 4)),
      ]),
      const SizedBox(height: 6),
      // RAM
      Row(children: [
        SizedBox(width: 32, child: Text('RAM', style: const TextStyle(fontSize: 11))),
        Expanded(child: AntdProgress(percent: memPct, color: AntdTokens.warning, strokeWidth: 4)),
        const SizedBox(width: 4),
        Text('${_formatBytes(memUsed)}/${_formatBytes(memTotal)}',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
      const SizedBox(height: 6),
      // DISK
      Row(children: [
        SizedBox(width: 32, child: Text('DISK', style: const TextStyle(fontSize: 11))),
        Expanded(child: AntdProgress(percent: diskPct, color: const Color(0xFF722ED1), strokeWidth: 4)),
        const SizedBox(width: 4),
        Text('${_formatBytes(diskUsed)}/${_formatBytes(diskTotal)}',
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
      const SizedBox(height: 6),
      // Network
      Row(children: [
        Expanded(child: Row(children: [
          const Icon(Icons.arrow_downward, size: 11, color: AntdTokens.success),
          const SizedBox(width: 2),
          Text('${_formatBytes(rxRate)}/s',
              style: const TextStyle(color: AntdTokens.success, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text('总 ${_formatBytes(rxTotal)}',
              style: TextStyle(fontSize: 10, color: AntdTokens.secondaryTextColor(ctx))),
        ])),
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const Icon(Icons.arrow_upward, size: 11, color: AntdTokens.primary),
          const SizedBox(width: 2),
          Text('${_formatBytes(txRate)}/s',
              style: const TextStyle(color: AntdTokens.primary, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text('总 ${_formatBytes(txTotal)}',
              style: TextStyle(fontSize: 10, color: AntdTokens.secondaryTextColor(ctx))),
        ])),
      ]),
      // Traffic limit
      if (limit > 0) ...[
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(width: 32,
              child: Text('\u6d41\u91cf', style: const TextStyle(fontSize: 11))),
          Expanded(child: AntdProgress(percent: trafficPct, strokeWidth: 4)),
          const SizedBox(width: 4),
          Text('${_formatBytes(trafficUsed)}/${_formatBytes(limit)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
        if (host.netResetDay > 0)
          Padding(padding: const EdgeInsets.only(top: 2),
              child: Text('\u6bcf\u6708${host.netResetDay}\u65e5\u91cd\u7f6e',
                  style: const TextStyle(fontSize: 9, color: AntdTokens.primary))),
      ],
      // Expiry + billing
      if (expDate != null || billingAmt > 0) ...[
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (expDate != null)
            Text('\u5230\u671f: ${expDate.split('T')[0]} (${daysLeft}d)',
                style: TextStyle(fontSize: 10, color: daysLeft <= 7 ? Colors.orange : Colors.grey)),
          if (billingAmt > 0)
            Text('${_getCurrencySymbol(currency)}${billingAmt.toStringAsFixed(2)} / ${billingPrd ?? ""}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
        if (expDate != null && billingAmt > 0 && billingPrd != null && billingPrd.isNotEmpty)
          Text('\u5269\u4f59\u4ef7\u503c: ${_getCurrencySymbol(currency)}$remainingVal',
              style: const TextStyle(fontSize: 9, color: AntdTokens.success)),
      ],
    ]);

    final cardActions = <AntdButton>[
      AntdButton(type: AntdButtonType.text, icon: Icons.show_chart,
          onPressed: () { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('\u7f51\u7edc\u8be6\u60c5\u5f85\u5b9e\u73b0'))); }),
      AntdButton(type: AntdButtonType.text, icon: Icons.code,
          onPressed: () { /* connect to host terminal */ },
          size: AntdSize.small),
      AntdButton(type: AntdButtonType.text, icon: Icons.history,
          onPressed: () { ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('\u72b6\u6001\u5386\u53f2\u5f85\u5b9e\u73b0'))); }),
      AntdButton(type: AntdButtonType.text, icon: Icons.settings,
          onPressed: () async { await state.stopMonitorAgent(hostId); }),
    ];

    return AntdMetricCard(
      title: host.name,
      value: isOnline ? 'ONLINE' : 'OFFLINE',
      status: isOnline ? AntdStatusBadgeStatus.online : AntdStatusBadgeStatus.offline,
      statusText: isOnline ? 'ONLINE' : 'OFFLINE',
      icon: Icons.dns_outlined,
      iconColor: isOnline ? AntdTokens.success : AntdTokens.secondaryTextColor(ctx),
      actions: cardActions,
      child: metricBody,
    );
  }

  String _formatUptime(int s) {
    final d = (s / 86400).floor(), h = ((s % 86400) / 3600).floor(), m = ((s % 3600) / 60).floor();
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatBytes(double b) {
    if (b <= 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(b) / log(k)).floor();
    return '${(b / pow(k, i)).toStringAsFixed(1)} ${sizes[i]}';
  }

  int _getDaysUntil(String ds) {
    try {
      return DateTime.parse(ds).difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  String _getCurrencySymbol(String c) => const {
    'CNY': '\u00a5', 'USD': '\$', 'EUR': '\u20ac', 'GBP': '\u00a3', 'JPY': '\u00a5',
  }[c] ?? '\u00a5';

  String _calculateRemainingValue(String exp, String period, double amt) {
    final days = _getDaysUntil(exp);
    if (days <= 0) return '0.00';
    final periodDays = {
      'monthly': 30, 'quarterly': 90, 'semiannually': 180, 'annually': 365,
      'biennial': 730, 'triennial': 1095,
    }[period] ?? 30;
    return ((amt / periodDays) * days).toStringAsFixed(2);
  }
}
