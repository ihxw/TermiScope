import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../providers/app_state.dart';
import '../utils/responsive.dart';

class MonitorTab extends StatelessWidget {
  const MonitorTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final monitorHosts = state.hosts.where((h) => h.monitorEnabled).toList();
        final onlineHosts = monitorHosts.where((h) {
          final hostId = h.id.toString();
          return state.monitorData.containsKey(hostId) && state.monitorData[hostId].isNotEmpty;
        }).length;
        
        return Column(
          children: [
            // Top Stats Bar (compact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF2D2D2D),
              child: Row(
                children: [
                   const Icon(Icons.app_registration, size: 16, color: Colors.grey),
                   const SizedBox(width: 6),
                   Text('Total: ${monitorHosts.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                   const SizedBox(width: 12),
                   const Text('|', style: TextStyle(color: Colors.grey, fontSize: 12)),
                   const SizedBox(width: 12),
                   Text('Online: $onlineHosts', style: const TextStyle(color: Color(0xFF32D74B), fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            
            Expanded(
              child: monitorHosts.isEmpty ? const Center(
                  child: Text('No monitored hosts.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ) : LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = Responsive.crossAxisCountFromWidth(constraints.maxWidth);

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 280,
                    ),
                    itemCount: monitorHosts.length,
                    itemBuilder: (context, index) {
                      final host = monitorHosts[index];
                      final hostId = host.id.toString();
                      final hostName = host.name;
                      
                      final monitorInfo = state.monitorData[hostId] ?? {};
                      final isOnline = monitorInfo.isNotEmpty;
                      
                      final double cpu = (monitorInfo['cpu'] ?? 0).toDouble();
                      double memUsed = (monitorInfo['mem_used'] ?? 0).toDouble();
                      double memTotal = (monitorInfo['mem_total'] ?? 1).toDouble();
                      double memPct = memTotal > 0 ? (memUsed / memTotal) * 100 : 0.0;

                      final String os = monitorInfo['os'] ?? 'Unknown';
                      final int uptime = monitorInfo['uptime'] ?? 0;
                      
                      double diskUsed = 0.0;
                      double diskTotal = 0.0;
                      if (monitorInfo['disks'] != null && (monitorInfo['disks'] as List).isNotEmpty) {
                         for (var disk in (monitorInfo['disks'] as List)) {
                            diskUsed += (disk['used'] ?? 0).toDouble();
                            diskTotal += (disk['total'] ?? 0).toDouble();
                         }
                      } else {
                         diskUsed = (monitorInfo['disk_used'] ?? 0).toDouble();
                         diskTotal = (monitorInfo['disk_total'] ?? 1).toDouble();
                      }
                      double diskPct = diskTotal > 0 ? (diskUsed / diskTotal) * 100 : 0.0;

                      final double rxRate = (monitorInfo['net_rx_rate'] ?? 0).toDouble();
                      final double txRate = (monitorInfo['net_tx_rate'] ?? 0).toDouble();
                      final double rxTotal = (monitorInfo['net_monthly_rx'] ?? 0).toDouble();
                      final double txTotal = (monitorInfo['net_monthly_tx'] ?? 0).toDouble();

                      final double trafficLimit = (host.netTrafficLimit ?? 0).toDouble();
                      final int resetDay = host.netResetDay;
                      final String counterMode = host.netTrafficCounterMode;
                      final double trafficUsedAdjustment = host.netTrafficUsedAdjustment;
                      
                      double measuredTraffic = 0;
                      if (counterMode == 'rx') {
                        measuredTraffic = rxTotal;
                      } else if (counterMode == 'tx') measuredTraffic = txTotal;
                      else measuredTraffic = rxTotal + txTotal;
                      
                      final double totalTrafficUsed = measuredTraffic + trafficUsedAdjustment;
                      final double trafficPct = trafficLimit > 0 ? (totalTrafficUsed / trafficLimit * 100).clamp(0, 100).toDouble() : 0.0;

                      final String? expirationDate = host.expirationDate;
                      final double billingAmount = host.billingAmount;
                      final String? billingPeriod = host.billingPeriod;
                      final String currency = host.currency;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(hostName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isOnline ? const Color(0xFF32D74B).withAlpha(51) : Colors.red.withAlpha(51),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          isOnline ? 'ONLINE' : 'OFFLINE',
                                          style: TextStyle(color: isOnline ? const Color(0xFF32D74B) : Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.desktop_windows, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(os, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.access_time, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(_formatUptime(uptime), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _buildMetricBar('CPU', cpu, const Color(0xFF64D2FF)),
                                  const SizedBox(height: 8),
                                  _buildMetricBar('RAM', memPct, const Color(0xFFFF9500), labelRight: '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}'),
                                  const SizedBox(height: 8),
                                  _buildMetricBar('DISK', diskPct, const Color(0xFFBF5AF2), labelRight: '${_formatBytes(diskUsed)} / ${_formatBytes(diskTotal)}'),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.arrow_downward, size: 11, color: Color(0xFF32D74B)),
                                                const SizedBox(width: 4),
                                                Text('${_formatBytes(rxRate)}/s', style: const TextStyle(color: Color(0xFF32D74B), fontSize: 11, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            Text('Total: ${_formatBytes(rxTotal)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                const Icon(Icons.arrow_upward, size: 11, color: Color(0xFF64D2FF)),
                                                const SizedBox(width: 4),
                                                Text('${_formatBytes(txRate)}/s', style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 11, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                            Text('Total: ${_formatBytes(txTotal)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (trafficLimit > 0) ...[
                              const Divider(height: 1, color: Color(0xFF2D2D2D)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Traffic (${trafficPct.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                        Text('${_formatBytes(totalTrafficUsed)} / ${_formatBytes(trafficLimit)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                    if (resetDay > 0)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('Reset on day $resetDay of month', style: const TextStyle(fontSize: 9, color: Color(0xFF64D2FF))),
                                      ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                      value: trafficPct / 100.0,
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      valueColor: AlwaysStoppedAnimation<Color>(trafficPct > 90 ? Colors.red : (trafficPct > 70 ? Colors.orange : const Color(0xFF32D74B))),
                                      minHeight: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (expirationDate != null || billingAmount > 0) ...[
                              const Divider(height: 1, color: Color(0xFF2D2D2D)),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (expirationDate != null)
                                          Row(
                                            children: [
                                              const Icon(Icons.event_available, size: 12, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Exp: ${expirationDate.split('T')[0]} (${_getDaysUntil(expirationDate)}d)',
                                                style: TextStyle(fontSize: 10, color: _getDaysUntil(expirationDate) <= 7 ? Colors.orange : Colors.grey),
                                              ),
                                            ],
                                          )
                                        else
                                          const SizedBox(),
                                        if (billingAmount > 0)
                                          Text(
                                            '${_getCurrencySymbol(currency)}${billingAmount.toStringAsFixed(2)} / ${billingPeriod ?? "period"}',
                                            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                    if (expirationDate != null && billingAmount > 0 && billingPeriod != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'Value: ${_getCurrencySymbol(currency)}${_calculateRemainingValue(expirationDate, billingPeriod, billingAmount)}',
                                          style: const TextStyle(fontSize: 9, color: Color(0xFF32D74B)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricBar(String label, double percent, Color color, {String? labelRight}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Text(labelRight ?? '${percent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percent / 100.0,
          backgroundColor: const Color(0xFF1E1E1E),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    );
  }

  String _formatUptime(int seconds) {
    final int dys = (seconds / 86400).floor();
    final int hrs = ((seconds % 86400) / 3600).floor();
    final int min = ((seconds % 3600) / 60).floor();
    if (dys > 0) return '${dys}d ${hrs}h';
    if (hrs > 0) return '${hrs}h ${min}m';
    return '${min}m';
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    const int k = 1024;
    const List<String> sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final int i = (log(bytes) / log(k)).floor();
    final double value = bytes / pow(k, i);
    return '${value.toStringAsFixed(1)} ${sizes[i]}';
  }

  int _getDaysUntil(String dateStr) {
    try {
      final expiry = DateTime.parse(dateStr);
      final now = DateTime.now();
      return expiry.difference(now).inDays;
    } catch (e) {
      return 0;
    }
  }

  String _getCurrencySymbol(String currency) {
    const symbols = {'CNY': '¥', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'JPY': '¥'};
    return symbols[currency] ?? '¥';
  }

  String _calculateRemainingValue(String expirationDate, String billingPeriod, double billingAmount) {
    final daysRemaining = _getDaysUntil(expirationDate);
    if (daysRemaining <= 0) return "0.00";
    final Map<String, int> periodDays = {
      'monthly': 30, 'quarterly': 90, 'semiannually': 180, 'annually': 365, 'biennial': 730, 'triennial': 1095
    };
    final days = periodDays[billingPeriod] ?? 30;
    final dailyRate = billingAmount / days;
    return (dailyRate * daysRemaining).toStringAsFixed(2);
  }
}
