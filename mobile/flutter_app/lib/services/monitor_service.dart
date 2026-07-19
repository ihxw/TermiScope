import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/realtime/realtime_url.dart';
import '../providers/app_state.dart';

class MonitorService {
  final AppState appState;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _disposed = false;

  MonitorService(this.appState);

  void connect() async {
    if (_isConnected || _disposed) return;
    final ticket = await appState.getTicket();
    final baseUrl = appState.apiService.baseUrl;
    if (ticket == null || baseUrl == null || baseUrl.isEmpty) {
      print(
          'MonitorService: missing ticket or baseUrl (ticket: $ticket, baseUrl: $baseUrl)');
      return;
    }
    final wsUrl = RealtimeUrl.build(
      baseUrl: baseUrl,
      path: '/api/monitor/stream',
      query: {'token': ticket},
    );

    try {
      _channel = WebSocketChannel.connect(wsUrl);
      _isConnected = true;
      appState.setMonitorConnected(true);
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            if (msg['type'] == 'init' || msg['type'] == 'update') {
              final raw = msg['data'];
              final updates = raw is List ? raw : [raw];
              for (final update in updates.whereType<Map>()) {
                appState.updateMonitorData(Map<String, dynamic>.from(update));
              }
            } else if (msg['type'] == 'offline') {
              appState.markMonitorOffline(msg['data']);
            } else if (msg['type'] == 'remove') {
              appState.removeMonitorHost(msg['data']);
            } else if (msg['type'] == 'agent_event' && msg['data'] is Map) {
              appState.setMonitorAgentStatus(
                msg['data']['host_id'],
                msg['data']['message'],
              );
            }
          } catch (e) {
            print('Parse error: $e');
          }
        },
        onError: (error) {
          print('Monitor ws error: $error');
          _isConnected = false;
          appState.setMonitorConnected(false);
          appState.markAllMonitorOffline();
          if (!_disposed) Future.delayed(const Duration(seconds: 3), connect);
        },
        onDone: () {
          print('Monitor ws closed');
          _isConnected = false;
          appState.setMonitorConnected(false);
          appState.markAllMonitorOffline();
          if (!_disposed) Future.delayed(const Duration(seconds: 3), connect);
        },
      );
    } catch (e) {
      print('Monitor connect error: $e');
      _isConnected = false;
      appState.setMonitorConnected(false);
    }
  }

  void disconnect() {
    _disposed = true;
    _isConnected = false;
    appState.setMonitorConnected(false);
    _channel?.sink.close();
    _channel = null;
  }
}
