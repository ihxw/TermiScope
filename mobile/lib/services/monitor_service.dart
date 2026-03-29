import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/ssh_host.dart';

class MonitorService {
  final ApiClient _apiClient = ApiClient.instance;

  MonitorService();

  // Get WebSocket ticket for monitor stream
  Future<String> getWSTicket() async {
    try {
      final response = await _apiClient.getWSTicket();
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { ticket: "..." } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('Invalid response format: no data');
        }
        final ticket = dataWrapper['ticket'] as String?;
        if (ticket == null || ticket.isEmpty) {
          throw Exception('Invalid response format: no ticket');
        }
        return ticket;
      }
      throw Exception('Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  // WebSocket connection management
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  Future<void> connect() async {
    disconnect(); // Ensure we close any existing connection
    
    try {
      final ticket = await getWSTicket();
      // Get base URL from preferences since _dio is private
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString(AppConstants.serverUrlKey) ?? AppConstants.defaultServerUrl;
      
      // Replace http/https with ws/wss
      final wsUrl = baseUrl.replaceFirst(RegExp(r'^https?:'), 'ws:') + '/api/monitor/stream';
      
      // Connect to WebSocket with ticket
      _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl),
        headers: {'Authorization': 'Bearer $ticket'}
      );
      
      // Listen to incoming messages
      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            // Handle the incoming data - this would typically trigger an update event
            // In a real implementation, we would broadcast this to listeners
          } catch (e) {
            print('Error parsing WebSocket message: ${e}');
          }
        },
        onError: (error) {
          print('WebSocket error: ${error}');
        },
        onDone: () {
          print('WebSocket connection closed');
        },
      );
    } catch (e) {
      print('Failed to connect to monitor WebSocket: ${e}');
    }
  }
  
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close();
    _subscription = null;
    _channel = null;
  }
  
  Stream<Map<String, dynamic>> get updates {
    if (_channel == null) {
      return const Stream.empty();
    }
    
    return _channel!.stream.transform(
      StreamTransformer<dynamic, Map<String, dynamic>>.fromHandlers(
        handleData: (data, sink) {
          try {
            if (data is String) {
              final parsed = jsonDecode(data);
              sink.add(parsed);
            }
          } catch (e) {
            sink.addError('Error parsing monitor data: ${e}');
          }
        },
      ),
    ).cast<Map<String, dynamic>>();
  }
  
  void dispose() {
    disconnect();
  }

  // Deploy monitor to host
  Future<bool> deployMonitor(int hostId, {bool insecure = false}) async {
    try {
      final response = await _apiClient.post(
        '/api/ssh-hosts/$hostId/monitor/deploy',
        data: {'insecure': insecure},
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Stop monitor on host
  Future<bool> stopMonitor(int hostId) async {
    try {
      final response = await _apiClient.post('/api/ssh-hosts/$hostId/monitor/stop');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Update agent on host
  Future<bool> updateAgent(int hostId) async {
    try {
      final response = await _apiClient.post('/api/ssh-hosts/$hostId/monitor/update');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get status logs for a host
  Future<List<Map<String, dynamic>>> getStatusLogs(int hostId, {int page = 1, int pageSize = 10}) async {
    try {
      final response = await _apiClient.get(
        '/api/ssh-hosts/$hostId/monitor/logs',
        params: {'page': page, 'page_size': pageSize},
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

  // Get traffic reset logs
  Future<List<Map<String, dynamic>>> getTrafficResetLogs() async {
    try {
      final response = await _apiClient.get('/api/monitor/traffic-reset-logs');
      
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

  // Get traffic reset debug info for host
  Future<Map<String, dynamic>> getTrafficResetDebug(int hostId) async {
    try {
      final response = await _apiClient.get('/api/monitor/traffic-reset-debug/$hostId');
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Force traffic reset for host
  Future<bool> forceTrafficReset(int hostId) async {
    try {
      final response = await _apiClient.post('/api/monitor/traffic-reset-force/$hostId');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get network tasks for a host
  Future<List<Map<String, dynamic>>> getHostNetworkTasks(int hostId) async {
    try {
      final response = await _apiClient.get('/api/ssh-hosts/$hostId/network/tasks');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['tasks'] != null) {
          return (data['tasks'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Create network task
  Future<Map<String, dynamic>> createNetworkTask(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/api/monitor/network/tasks', data: data);
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Update network task
  Future<Map<String, dynamic>> updateNetworkTask(int taskId, Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.put('/api/monitor/network/tasks/$taskId', data: data);
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Delete network task
  Future<bool> deleteNetworkTask(int taskId) async {
    try {
      final response = await _apiClient.delete('/api/monitor/network/tasks/$taskId');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get task statistics
  Future<Map<String, dynamic>> getTaskStats(int taskId, {String range = '24h'}) async {
    try {
      final response = await _apiClient.get('/api/monitor/network/stats/$taskId', 
        params: {'range': range});
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Get network templates
  Future<List<Map<String, dynamic>>> getNetworkTemplates() async {
    try {
      final response = await _apiClient.get('/api/monitor/network/templates');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['templates'] != null) {
          return (data['templates'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Create network template
  Future<Map<String, dynamic>> createNetworkTemplate(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/api/monitor/network/templates', data: data);
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Update network template
  Future<Map<String, dynamic>> updateNetworkTemplate(int templateId, Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.put('/api/monitor/network/templates/$templateId', data: data);
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  // Delete network template
  Future<bool> deleteNetworkTemplate(int templateId) async {
    try {
      final response = await _apiClient.delete('/monitor/network/templates/$templateId');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get template assignments
  Future<List<Map<String, dynamic>>> getTemplateAssignments(int templateId) async {
    try {
      final response = await _apiClient.get('/monitor/network/templates/$templateId/assignments');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['assignments'] != null) {
          return (data['assignments'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Batch apply template
  Future<bool> batchApplyTemplate(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/monitor/network/apply-template', data: data);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}