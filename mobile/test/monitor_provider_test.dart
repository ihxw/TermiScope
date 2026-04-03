import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/lib/providers/monitor_provider.dart';
import 'package:mobile/lib/models/monitor_host.dart';

// Minimal mock implementations to test MonitorProvider logic
class MockMonitorService {
  final Map<int, bool> updateResults;
  MockMonitorService([this.updateResults = const {}]);

  Future<bool> updateAgent(int hostId) async {
    await Future.delayed(Duration(milliseconds: 1));
    return updateResults[hostId] ?? true;
  }

  Future<List<Map<String, dynamic>>> getHostNetworkTasks(int hostId) async {
    return [];
  }

  Future<Map<String, dynamic>> createNetworkTask(Map<String, dynamic> data) async {
    return {'id': 123, ...data};
  }

  Future<Map<String, dynamic>> updateNetworkTask(int taskId, Map<String, dynamic> data) async {
    return {'id': taskId, ...data};
  }

  Future<bool> deleteNetworkTask(int taskId) async {
    return true;
  }

  Future<Map<String, dynamic>> getTaskStats(int taskId, {String range = '24h'}) async {
    return {'task_id': taskId, 'range': range, 'values': [1,2,3]};
  }

  Future<List<Map<String, dynamic>>> getNetworkTemplates() async => [];
  Future<bool> batchApplyTemplate(Map<String, dynamic> data) async => true;
  Future<List<Map<String, dynamic>>> getTrafficResetLogs() async => [];
  Future<Map<String, dynamic>> getTrafficResetDebug(int hostId) async => {};
  Future<bool> forceTrafficReset(int hostId) async => true;

  void connect() {}
  void dispose() {}
  Stream<Map<String, dynamic>> get updates => const Stream.empty();
}

class MockHostService {
  Future<List<dynamic>> getHosts() async => [];
}

void main() {
  test('batchUpdateAgents counts successes', () async {
    final mockService = MockMonitorService({1: true, 2: false, 3: true});
    final provider = MonitorProvider(mockService as dynamic, MockHostService() as dynamic);

    // set hosts for testing
    provider.setHostsForTesting([
      MonitorHost(
        hostId: 1,
        hostname: 'h1',
        name: 'Host1',
        os: 'linux',
        uptime: 1000,
        cpu: 1.0,
        cpuCount: 2,
        cpuModel: 'x',
        memUsed: 1,
        memTotal: 2,
        diskUsed: 1,
        diskTotal: 2,
        netRxRate: 0,
        netTxRate: 0,
        netMonthlyRx: 0,
        netMonthlyTx: 0,
        lastUpdated: '0',
        agentVersion: '',
        netTrafficLimit: 0,
        netTrafficCounterMode: 'total',
        netTrafficUsedAdjustment: 0,
        expirationDate: null,
        billingPeriod: null,
        billingAmount: 0,
        currency: 'USD',
        flag: '',
      ),
      MonitorHost(
        hostId: 2,
        hostname: 'h2',
        name: 'Host2',
        os: 'linux',
        uptime: 1000,
        cpu: 1.0,
        cpuCount: 2,
        cpuModel: 'x',
        memUsed: 1,
        memTotal: 2,
        diskUsed: 1,
        diskTotal: 2,
        netRxRate: 0,
        netTxRate: 0,
        netMonthlyRx: 0,
        netMonthlyTx: 0,
        lastUpdated: '0',
        agentVersion: '',
        netTrafficLimit: 0,
        netTrafficCounterMode: 'total',
        netTrafficUsedAdjustment: 0,
        expirationDate: null,
        billingPeriod: null,
        billingAmount: 0,
        currency: 'USD',
        flag: '',
      ),
      MonitorHost(
        hostId: 3,
        hostname: 'h3',
        name: 'Host3',
        os: 'linux',
        uptime: 1000,
        cpu: 1.0,
        cpuCount: 2,
        cpuModel: 'x',
        memUsed: 1,
        memTotal: 2,
        diskUsed: 1,
        diskTotal: 2,
        netRxRate: 0,
        netTxRate: 0,
        netMonthlyRx: 0,
        netMonthlyTx: 0,
        lastUpdated: '0',
        agentVersion: '',
        netTrafficLimit: 0,
        netTrafficCounterMode: 'total',
        netTrafficUsedAdjustment: 0,
        expirationDate: null,
        billingPeriod: null,
        billingAmount: 0,
        currency: 'USD',
        flag: '',
      ),
    ]);

    final count = await provider.batchUpdateAgents();
    expect(count, 2);
  });

  test('network task CRUD via provider', () async {
    final mockService = MockMonitorService();
    final provider = MonitorProvider(mockService as dynamic, MockHostService() as dynamic);

    final created = await provider.createNetworkTask({'host_id': 1, 'name': 't1'});
    expect(created['id'], 123);

    final updated = await provider.updateNetworkTask(123, {'name': 't1mod'});
    expect(updated['id'], 123);

    final deleted = await provider.deleteNetworkTask(123);
    expect(deleted, true);

    final stats = await provider.getTaskStats(123);
    expect(stats['task_id'], 123);
  });
}
