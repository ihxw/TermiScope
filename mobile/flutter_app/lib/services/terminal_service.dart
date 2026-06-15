import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/realtime/realtime_url.dart';
import '../providers/app_state.dart';

class TerminalService {
  final AppState appState;
  final String hostId;
  final bool record;
  WebSocketChannel? _channel;
  Function(String text)? onData;

  TerminalService(this.appState, this.hostId, {this.record = false});

  Future<bool> connect() async {
    final ticket = await appState.getTicket();
    if (ticket == null || appState.apiService.baseUrl == null) return false;

    final wsUrl = RealtimeUrl.build(
      baseUrl: appState.apiService.baseUrl!,
      path: '/api/ws/ssh/$hostId',
      query: {
        'ticket': ticket,
        if (record) 'record': 'true',
      },
    );

    try {
      _channel = WebSocketChannel.connect(wsUrl);
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            try {
              final msg = jsonDecode(data);
              if (msg['type'] == 'connected' || msg['type'] == 'error') {
                onData?.call(
                    '\r\n[${msg['type'].toUpperCase()}] ${msg['data']}\r\n');
              } else if (msg['type'] == 'data') {
                // Handle data type messages separately
                onData?.call(msg['data']?.toString() ?? '');
              }
              // Skip calling onData for already-handled message types to avoid duplicates
            } catch (e) {
              // If JSON parsing fails, treat as raw data
              onData?.call(data);
            }
          } else if (data is List<int>) {
            onData?.call(utf8.decode(data, allowMalformed: true));
          }
        },
        onError: (error) {
          onData?.call('\r\n[Connection Error]\r\n');
        },
        onDone: () {
          onData?.call('\r\n[Connection Closed]\r\n');
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  void write(String data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'type': 'input', 'data': data}));
    }
  }

  void resize(int cols, int rows) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'resize',
        'data': {'cols': cols, 'rows': rows}
      }));
    }
  }

  void dispose() {
    _channel?.sink.close();
  }
}
