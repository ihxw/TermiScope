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
                      const SizedBox(height: 16),
                      // Metrics
                      _buildMetricBar('CPU', cpu, const Color(0xFF64D2FF)),
                      const SizedBox(height: 12),
                      _buildMetricBar('RAM', memPct, const Color(0xFFFF9500), labelRight: '${_formatBytes(memUsed)} / ${_formatBytes(memTotal)}'),
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

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    const int k = 1024;
    const List<String> sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final int i = (log(bytes) / log(k)).floor();
    final double value = bytes / pow(k, i);
    return '${value.toStringAsFixed(1)} ${sizes[i]}';
  }
}
