import '../core/api_client.dart';
import '../models/ssh_host.dart';

class HostService {
  final ApiClient _apiClient = ApiClient.instance;

  HostService();

  Future<List<SSHHost>> getHosts({Map<String, dynamic>? filters}) async {
    try {
      final response = await _apiClient.get('/ssh-hosts', params: filters);
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['hosts'] != null) {
          return (data['hosts'] as List)
              .map((json) => SSHHost.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<SSHHost> getHost(int id, {bool reveal = false}) async {
    try {
      final params = reveal ? {'reveal': 'true'} : null;
      final response = await _apiClient.get('/ssh-hosts/$id', params: params);
      
      if (response.statusCode == 200 && response.data != null) {
        return SSHHost.fromJson(response.data);
      } else {
        throw Exception('Failed to get host');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<SSHHost> createHost(SSHHost host) async {
    try {
      final response = await _apiClient.post('/ssh-hosts', data: host.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return SSHHost.fromJson(response.data);
      } else {
        throw Exception('Failed to create host');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<SSHHost> updateHost(int id, SSHHost host) async {
    try {
      final response = await _apiClient.put('/ssh-hosts/$id', data: host.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return SSHHost.fromJson(response.data);
      } else {
        throw Exception('Failed to update host');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteHost(int id) async {
    try {
      final response = await _apiClient.delete('/ssh-hosts/$id');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> permanentDeleteHost(int id) async {
    try {
      final response = await _apiClient.delete('/ssh-hosts/$id/permanent');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> testConnection(int id) async {
    try {
      final response = await _apiClient.post('/ssh-hosts/$id/test');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deployMonitor(int id, {bool insecure = false}) async {
    try {
      final response = await _apiClient.post('/ssh-hosts/$id/monitor/deploy', 
        data: {'insecure': insecure});
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> stopMonitor(int id) async {
    try {
      final response = await _apiClient.post('/ssh-hosts/$id/monitor/stop');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateAgent(int id) async {
    try {
      final response = await _apiClient.post('/ssh-hosts/$id/monitor/update');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateHostFingerprint(int id, String fingerprint) async {
    try {
      final response = await _apiClient.put('/ssh-hosts/$id/fingerprint', 
        data: {'fingerprint': fingerprint});
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getStatusLogs(int id, {int page = 1, int pageSize = 10}) async {
    try {
      final response = await _apiClient.get(
        '/ssh-hosts/$id/monitor/logs',
        params: {'page': page, 'page_size': pageSize}
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['logs'] != null) {
          return (data['logs'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<int>> reorderHosts(List<int> ids) async {
    try {
      final response = await _apiClient.put('/ssh-hosts/reorder', 
        data: {'device_ids': ids});
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['ordered_ids'] != null) {
          return (data['ordered_ids'] as List).cast<int>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }
}