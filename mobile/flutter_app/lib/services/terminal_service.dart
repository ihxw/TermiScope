import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/realtime/realtime_url.dart';
import '../providers/app_state.dart';

class TerminalService {
  final AppState appState;
  final String hostId;
  final bool record;
  WebSocketChannel? _channel;
  void Function(String text)? onData;
  void Function(String status)? onStatusChanged;
  final StringBuffer _inputBuffer = StringBuffer();
  Timer? _inputFlushTimer;

  TerminalService(this.appState, this.hostId, {this.record = false});

  Future<bool> connect() async {
    onStatusChanged?.call('Connecting...');
    final ticket = await appState.getTicket();
    if (ticket == null || appState.apiService.baseUrl == null) {
      onStatusChanged?.call('Error');
      return false;
    }

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
          onStatusChanged?.call('Error');
          onData?.call('\r\n[Connection Error]\r\n');
        },
        onDone: () {
          onStatusChanged?.call('Disconnected');
          onData?.call('\r\n[Connection Closed]\r\n');
        },
      );
      onStatusChanged?.call('Connected');
      return true;
    } catch (e) {
      onStatusChanged?.call('Error');
      return false;
    }
  }

  void write(String data) {
    if (_channel == null || data.isEmpty) return;
    _inputBuffer.write(data);
    if (_shouldFlushInputImmediately(data)) {
      _flushInput();
      return;
    }
    _inputFlushTimer ??= Timer(const Duration(milliseconds: 8), _flushInput);
  }

  bool _shouldFlushInputImmediately(String data) {
    return data.contains('\r') ||
        data.contains('\n') ||
        data.contains('\x03') ||
        data.contains('\x04') ||
        data.startsWith('\x1b');
  }

  void _flushInput() {
    _inputFlushTimer?.cancel();
    _inputFlushTimer = null;
    if (_channel == null || _inputBuffer.isEmpty) return;
    final data = _inputBuffer.toString();
    _inputBuffer.clear();
    _channel!.sink.add(jsonEncode({'type': 'input', 'data': data}));
  }

  void resize(int cols, int rows) {
    _flushInput();
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'resize',
        'data': {'cols': cols, 'rows': rows}
      }));
    }
  }

  void dispose() {
    _flushInput();
    _inputFlushTimer?.cancel();
    _inputFlushTimer = null;
    _channel?.sink.close();
    _channel = null;
    onStatusChanged?.call('Disconnected');
  }
}
