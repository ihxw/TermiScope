import '../api/api_client.dart';
import '../models/ssh_host.dart';

/// SSH 主机服务
class HostService {
  final ApiClient _apiClient;

  HostService(this._apiClient);

  /// 获取主机列表
  Future<List<SshHost>> getHosts({String? group, String? search}) async {
    final params = <String, String>{};
    if (group != null) params['group'] = group;
    if (search != null) params['search'] = search;

    final response =
        await _apiClient.get('/ssh-hosts', queryParameters: params);

    // 后端返回 { list: [...], total: ... }
    final listRaw = response is Map ? response['list'] : response;
    final list = (listRaw as List?) ?? [];

    return list.map((json) => SshHost.fromJson(json)).toList();
  }

  /// 获取单个主机
  Future<SshHost> getHost(int id) async {
    final response = await _apiClient.get('/ssh-hosts/$id');
    return SshHost.fromJson(response);
  }

  /// 创建主机
  Future<SshHost> createHost(Map<String, dynamic> data) async {
    final response = await _apiClient.post('/ssh-hosts', data: data);
    return SshHost.fromJson(response);
  }

  /// 更新主机
  Future<SshHost> updateHost(int id, Map<String, dynamic> data) async {
    final response = await _apiClient.put('/ssh-hosts/$id', data: data);
    return SshHost.fromJson(response);
  }

  /// 删除主机
  Future<void> deleteHost(int id) async {
    await _apiClient.delete('/ssh-hosts/$id');
  }

  /// 测试连接
  Future<Map<String, dynamic>> testConnection(int id) async {
    final response = await _apiClient.post('/ssh-hosts/$id/test');
    return response;
  }

  /// 部署监控
  Future<void> deployMonitor(int id, {bool insecure = false}) async {
    await _apiClient
        .post('/ssh-hosts/$id/monitor/deploy', data: {'insecure': insecure});
  }

  /// 停止监控
  Future<void> stopMonitor(int id) async {
    await _apiClient.post('/ssh-hosts/$id/monitor/stop');
  }

  /// 批量部署监控
  Future<void> batchDeployMonitor(List<int> hostIds,
      {bool insecure = false}) async {
    await _apiClient.post('/ssh-hosts/monitor/batch-deploy', data: {
      'host_ids': hostIds,
      'insecure': insecure,
    });
  }

  /// 批量停止监控
  Future<void> batchStopMonitor(List<int> hostIds) async {
    await _apiClient.post('/ssh-hosts/monitor/batch-stop', data: {
      'host_ids': hostIds,
    });
  }

  /// 重新排序主机
  Future<void> reorderHosts(List<int> ids) async {
    await _apiClient.put('/ssh-hosts/reorder', data: {'device_ids': ids});
  }
}
