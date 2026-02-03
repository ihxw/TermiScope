import 'package:flutter/material.dart';
import '../data/models/monitor_host.dart';
import '../data/services/monitor_service.dart';

class MonitorProvider extends ChangeNotifier {
  final MonitorService _service;
  List<MonitorHost> _hosts = [];
  bool _isConnected = false;

  List<MonitorHost> get hosts => _hosts;
  bool get isConnected => _isConnected;

  MonitorProvider(this._service);

  void connect() {
    _service.connect();
    _isConnected = true;
    _service.updates.listen(_handleUpdate);
  }

  void disconnect() {
    _service.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  void _handleUpdate(Map<String, dynamic> msg) {
    final type = msg['type'];
    final data = msg['data'];

    if (type == 'init') {
      // Full list replacement
      if (data is List) {
        _hosts = data.map((json) => MonitorHost.fromJson(json)).toList();
        notifyListeners();
      }
    } else if (type == 'update') {
      // Partial update
      if (data is List) {
        for (var updateJson in data) {
          final hostId = updateJson['host_id'];
          final index = _hosts.indexWhere((h) => h.hostId == hostId);

          if (index != -1) {
            // Merge/Replace logic
            // Backend sends full struct for the changed host usually in 'update' event based on Vue code
            // But let's check MonitorDashboard.vue:717 -> It merges: hosts.value[index] = { ...hosts.value[index], ...update }
            // Here we use copyWith or just create new object if it's full data.
            // MonitorHost.fromJson handles missing fields with defaults, which might be wrong for partial updates.
            // However, our model is immutable. We need a way to merge map into existing object.
            // Simpler approach for now: Since MonitorHost fields are all either replaced or ignored,
            // and the backend likely sends the snapshot of metrics.
            // Let's create a helper to merge map into MonitorHost
            _hosts[index] = _mergeHost(_hosts[index], updateJson);
          } else {
            // New host appearing?
            _hosts.add(MonitorHost.fromJson(updateJson));
          }
        }
        notifyListeners();
      }
    } else if (type == 'remove') {
      // data is hostId, or object? Vue says: removeHost(msg.data)
      // msg.data might be ID.
      // Let's assume ID for now, need to verify backend if needed.
    }
  }

  MonitorHost _mergeHost(MonitorHost existing, Map<String, dynamic> update) {
    return MonitorHost(
      hostId: existing.hostId, // ID shouldn't change
      hostname: update['hostname'] ?? existing.hostname,
      os: update['os'] ?? existing.os,
      uptime: update['uptime'] ?? existing.uptime,
      cpu: (update['cpu'] ?? existing.cpu).toDouble(),
      cpuCount: update['cpu_count'] ?? existing.cpuCount,
      cpuModel: update['cpu_model'] ?? existing.cpuModel,
      memUsed: (update['mem_used'] ?? existing.memUsed).toDouble(),
      memTotal: (update['mem_total'] ?? existing.memTotal).toDouble(),
      diskUsed: (update['disk_used'] ?? existing.diskUsed).toDouble(),
      diskTotal: (update['disk_total'] ?? existing.diskTotal).toDouble(),
      netRxRate: (update['net_rx_rate'] ?? existing.netRxRate).toDouble(),
      netTxRate: (update['net_tx_rate'] ?? existing.netTxRate).toDouble(),
      netMonthlyRx: (update['net_monthly_rx'] ?? existing.netMonthlyRx)
          .toDouble(),
      netMonthlyTx: (update['net_monthly_tx'] ?? existing.netMonthlyTx)
          .toDouble(), // Fixed Typo
      lastUpdated: update['last_updated'] ?? existing.lastUpdated,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
