import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:logger/logger.dart';
import '../models/ssh_host.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// WebSocket 服务 - 用于实时监控数据
class WebSocketService {
  final AuthService _authService;
  final StorageService _storageService;
  final Logger _logger = Logger();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  final _dataController = StreamController<Map<int, MonitorData>>.broadcast();
  Stream<Map<int, MonitorData>> get dataStream => _dataController.stream;

  WebSocketService(this._authService, this._storageService);

  /// 连接到监控 WebSocket
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      // 获取 WebSocket 票据
      final ticket = await _authService.getWSTicket();

      // 构建 WebSocket URL
      final serverUrl = _storageService.getServerUrl();
      if (serverUrl == null) {
        throw Exception('服务器地址未设置');
      }

      final wsUrl = serverUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');

      final uri = Uri.parse('$wsUrl/api/monitor/stream?token=$ticket');

      _logger.i('[WS] Connecting to $uri');

      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _reconnectAttempts = 0;

      // 监听消息
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // 启动心跳
      _startHeartbeat();

      _logger.i('[WS] Connected');
    } catch (e) {
      _logger.e('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'];

      if (type == 'update' || type == 'init') {
        final List<dynamic> hostList = data['data'];
        final result = <int, MonitorData>{};

        for (var item in hostList) {
          final monitorData = MonitorData.fromJson(item);
          if (monitorData.hostId != null) {
            result[monitorData.hostId!] = monitorData;
          }
        }

        _dataController.add(result);
      }
    } catch (e) {
      _logger.e('[WS] Message parse error: $e');
    }
  }

  void _handleError(dynamic error) {
    _logger.e('[WS] Error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  void _handleDone() {
    _logger.i('[WS] Connection closed');
    _isConnected = false;
    _stopHeartbeat();

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected && _channel != null) {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _logger.w('[WS] Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (_reconnectAttempts + 1) * 2);
    _reconnectAttempts++;

    _logger.i(
        '[WS] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  /// 断开连接
  void disconnect() {
    _shouldReconnect = false;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _dataController.close();
  }
}
