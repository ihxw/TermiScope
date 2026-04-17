import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../providers/app_state.dart';

class MonitorTab extends StatelessWidget {
  const MonitorTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Consumer<AppState>(
        builder: (context, state, child) {
          final monitorHosts = state.hosts.where((h) => h['monitor_enabled'] == true).toList();
          
          if (monitorHosts.isEmpty) {
            return const Center(
              child: Text(
                'No monitored hosts.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: monitorHosts.length,
            itemBuilder: (context, index) {
              final host = monitorHosts[index];
              final hostId = host['id'].toString();
              final hostName = host['name'] ?? 'Unknown';
              
              final monitorInfo = state.monitorData[hostId] ?? {};
              final isOnline = monitorInfo.isNotEmpty; // Simplify online check
              
              final cpu = monitorInfo['cpu'] ?? 0.0;
              
              double memUsed = (monitorInfo['mem_used'] ?? 0).toDouble();
              double memTotal = (monitorInfo['mem_total'] ?? 1).toDouble();
              double memPct = memTotal > 0 ? (memUsed / memTotal) * 100 : 0.0;

              final String os = monitorInfo['os'] ?? 'Unknown';
              final int uptime = monitorInfo['uptime'] ?? 0;
              
              double diskUsed = 0.0;
              double diskTotal = 0.0;
              
              // Handle multiple disks or single disk
              if (monitorInfo['disks'] != null && (monitorInfo['disks'] as List).isNotEmpty) {
                 final disks = monitorInfo['disks'] as List;
                 for (var disk in disks) {
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

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            hostName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF32D74B).withAlpha(51) : Colors.red.withAlpha(51),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: TextStyle(
                                color: isOnline ? const Color(0xFF32D74B) : Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // OS and Uptime
                      Row(
                        children: [
                          Icon(Icons.desktop_windows, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(os, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(_formatUptime(uptime), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Metrics
                      _buildMetricBar('CPU', cpu, const Color(0xFF64D2FF)),
                      const SizedBox(height: 12),
                      _buildMetricBar('RAM', memPct, const Color(0xFFFF9500), labelRight: '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}'),
                      const SizedBox(height: 12),
                      _buildMetricBar('DISK', diskPct, const Color(0xFFBF5AF2), labelRight: '${_formatBytes(diskUsed)} / ${_formatBytes(diskTotal)}'),
                      const SizedBox(height: 16),
                      // Network Speed
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.arrow_downward, size: 12, color: Color(0xFF32D74B)),
                                    const SizedBox(width: 4),
                                    Text('${_formatBytes(rxRate)}/s', style: const TextStyle(color: Color(0xFF32D74B), fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 2),
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
                                    const Icon(Icons.arrow_upward, size: 12, color: Color(0xFF64D2FF)),
                                    const SizedBox(width: 4),
                                    Text('${_formatBytes(txRate)}/s', style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('Total: ${_formatBytes(txTotal)}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMetricBar(String label, double percent, Color color, {String? labelRight}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(labelRight ?? '${percent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percent / 100.0,
          backgroundColor: const Color(0xFF1E1E1E),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 6,
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
}
