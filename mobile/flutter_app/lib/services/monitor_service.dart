import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/app_state.dart';

class MonitorService {
  final AppState appState;
  WebSocketChannel? _channel;
  bool _isConnected = false;

  MonitorService(this.appState);

  void connect() async {
    if (_isConnected) return;
    final ticket = await appState.getTicket();
    final baseUrl = appState.apiService.baseUrl;
    if (ticket == null || baseUrl == null || baseUrl.isEmpty) {
      print('MonitorService: missing ticket or baseUrl (ticket: $ticket, baseUrl: $baseUrl)');
      return;
    }
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    // TermiScope web uses /api/monitor/stream
    final wsUrl = '$wsScheme://${uri.authority}/api/monitor/stream?token=$ticket';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            if (msg['type'] == 'init' || msg['type'] == 'update') {
              final list = msg['data'] as List;
              for (var update in list) {
                appState.updateMonitorData(update);
              }
            }
          } catch(e) {
            print('Parse error: $e');
          }
        },
        onError: (error) {
          print('Monitor ws error: $error');
          _isConnected = false;
          Future.delayed(const Duration(seconds: 3), connect);
        },
        onDone: () {
          print('Monitor ws closed');
          _isConnected = false;
          Future.delayed(const Duration(seconds: 3), connect);
        },
      );
    } catch (e) {
      print('Monitor connect error: $e');
      _isConnected = false;
    }
  }

  void disconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
  }
}
