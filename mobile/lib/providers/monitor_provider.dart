import 'package:flutter/material.dart';

import '../models/monitor_host.dart';
import '../services/monitor_service.dart';
import '../services/host_service.dart';

class MonitorProvider extends ChangeNotifier {
  final MonitorService _service;
  final HostService _hostService;
  List<MonitorHost> _hosts = [];
  Map<int, String> _hostNames = {};
  Map<int, String> _hostTypes = {}; // hostId -> hostType
  List<int> _hostOrder = []; // Sorted host IDs from HostService
  bool _isConnected = false;
  bool _batchUpdating = false;

  bool get batchUpdating => _batchUpdating;

  List<MonitorHost> get hosts {
    // Sort based on _hostOrder from HostService
    if (_hostOrder.isEmpty) return _hosts;

    final sorted = <MonitorHost>[];
    for (final hostId in _hostOrder) {
      final host = _hosts.cast<MonitorHost?>().firstWhere(
        (h) => h?.hostId == hostId,
        orElse: () => null,
      );
      if (host != null) sorted.add(host);
    }
    // Append any hosts not in _hostOrder (shouldn't happen normally)
    for (final host in _hosts) {
      if (!_hostOrder.contains(host.hostId)) {
        sorted.add(host);
      }
    }
    return sorted;
  }

  bool get isConnected => _isConnected;

  String getHostType(int hostId) => _hostTypes[hostId] ?? 'control_monitor';

  MonitorProvider(this._service, this._hostService);

  Future<void> connect() async {
    // 1. Fetch static host names, types, and order
    try {
      final hostsList = await _hostService.getHosts();
      _hostNames = {for (var h in hostsList) h.id: h.name};
      _hostTypes = {for (var h in hostsList) h.id: 'ssh'}; // Default to ssh type
      _hostOrder = hostsList
          .map((h) => h.id)
          .toList(); // Preserve order from server
    } catch (e) {
      print('Failed to fetch host metadata: $e');
    }

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
      if (data is List) {
        _hosts = data.map((json) {
          final h = MonitorHost.fromJson(json);
          return h.copyWith(name: _hostNames[h.hostId] ?? h.hostname);
        }).toList();
        notifyListeners();
      }
    } else if (type == 'update') {
      if (data is List) {
        for (var updateJson in data) {
          final hostId = updateJson['host_id'];
          final index = _hosts.indexWhere((h) => h.hostId == hostId);

          if (index != -1) {
            try {
              _hosts[index] = _mergeHost(_hosts[index], updateJson);
            } catch (e) {
              // Handle potential hot-reload schema mismatch or other errors
              // by recreating the host from scratch
              print('Monitor merge error (likely hot-reload): $e');
              final h = MonitorHost.fromJson(updateJson);
              _hosts[index] = h.copyWith(
                name: _hostNames[h.hostId] ?? h.hostname,
              );
            }
          } else {
            // New host
            final h = MonitorHost.fromJson(updateJson);
            _hosts.add(h.copyWith(name: _hostNames[h.hostId] ?? h.hostname));
          }
        }
        notifyListeners();
      }
    } else if (type == 'remove') {
      // Handle remove if needed
      if (data is int) {
        _hosts.removeWhere((h) => h.hostId == data);
        notifyListeners();
      }
    }
  }

  MonitorHost _mergeHost(MonitorHost existing, Map<String, dynamic> update) {
    return MonitorHost(
      hostId: existing.hostId,
      hostname: update['hostname'] ?? existing.hostname,
      name:
          _hostNames[existing.hostId] ??
          existing.name, // Ensure name is kept or updated
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
          .toDouble(),
      lastUpdated: update['last_updated'] ?? existing.lastUpdated,
      // Add missing fields merging
      agentVersion: update['agent_version'] ?? existing.agentVersion,
      netTrafficLimit: (update['net_traffic_limit'] ?? existing.netTrafficLimit)
          .toDouble(),
      netTrafficCounterMode:
          update['net_traffic_counter_mode'] ?? existing.netTrafficCounterMode,
      netTrafficUsedAdjustment:
          (update['net_traffic_used_adjustment'] ??
                  existing.netTrafficUsedAdjustment)
              .toDouble(),
      expirationDate: update['expiration_date'] ?? existing.expirationDate,
      billingPeriod: update['billing_period'] ?? existing.billingPeriod,
      billingAmount: (update['billing_amount'] ?? existing.billingAmount)
          .toDouble(),
      currency: update['currency'] ?? existing.currency,
      flag: update['flag'] ?? existing.flag,
    );
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  // Batch update agents for all hosts (returns number of successes)
  Future<int> batchUpdateAgents() async {
    _batchUpdating = true;
    notifyListeners();

    int successCount = 0;
    for (final h in _hosts) {
      try {
        final ok = await _service.updateAgent(h.hostId);
        if (ok) successCount++;
      } catch (e) {
        // continue on error
      }
    }

    _batchUpdating = false;
    notifyListeners();
    return successCount;
  }

  // Test helper: set hosts directly for unit tests
  void setHostsForTesting(List<MonitorHost> hosts) {
    _hosts = hosts;
    _hostOrder = hosts.map((h) => h.hostId).toList();
    _hostNames = {for (var h in hosts) h.hostId: h.name};
    _hostTypes = {for (var h in hosts) h.hostId: 'ssh'};
    notifyListeners();
  }

  // Network tasks helpers
  Future<List<Map<String, dynamic>>> getHostNetworkTasks(int hostId) async {
    try {
      return await _service.getHostNetworkTasks(hostId);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createNetworkTask(Map<String, dynamic> data) async {
    try {
      return await _service.createNetworkTask(data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateNetworkTask(int taskId, Map<String, dynamic> data) async {
    try {
      return await _service.updateNetworkTask(taskId, data);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteNetworkTask(int taskId) async {
    try {
      return await _service.deleteNetworkTask(taskId);
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getTaskStats(int taskId, {String range = '24h'}) async {
    try {
      return await _service.getTaskStats(taskId, range: range);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getNetworkTemplates() async {
    try {
      return await _service.getNetworkTemplates();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> batchApplyTemplate(Map<String, dynamic> data) async {
    try {
      return await _service.batchApplyTemplate(data);
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchTrafficResetLogs() async {
    try {
      return await _service.getTrafficResetLogs();
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchTrafficResetDebug(int hostId) async {
    try {
      return await _service.getTrafficResetDebug(hostId);
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> forceTrafficReset(int hostId) async {
    try {
      return await _service.forceTrafficReset(hostId);
    } catch (e) {
      return false;
    }
  }
}
