import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../../../core/models/ssh_host.dart';
import '../../../core/providers/hosts_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../widgets/virtual_keyboard.dart';

class SshTerminalPage extends ConsumerStatefulWidget {
  final int hostId;
  final SshHost? host;

  const SshTerminalPage({
    super.key,
    required this.hostId,
    this.host,
  });

  @override
  ConsumerState<SshTerminalPage> createState() => _SshTerminalPageState();
}

class _SshTerminalPageState extends ConsumerState<SshTerminalPage> {
  late final Terminal _terminal;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
    );
    _connect();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      if (_isConnected) return;

      final host = widget.host ??
          ref
              .read(hostsStateProvider)
              .hosts
              .firstWhere((h) => h.id == widget.hostId);

      _terminal.write('Connecting to ${host.host}:${host.port}...\r\n');
      _connectViaWebSocket(host);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _terminal.write('Error: $e\r\n');
        });
      }
    }
  }

  Future<void> _connectViaWebSocket(SshHost host) async {
    try {
      final authService = ref.read(authServiceProvider);
      final storageService = ref.read(storageServiceProvider);

      // 1. 获取 Ticket
      _terminal.write('Requesting access ticket...\r\n');
      final ticket = await authService.getWSTicket();

      // 2. 构建 WebSocket URL
      final serverUrl = storageService.getServerUrl();
      if (serverUrl == null) throw Exception('Server URL not set');

      final wsUrl = serverUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');

      final uri = Uri.parse('$wsUrl/api/ws/ssh/${host.id}?ticket=$ticket');

      _terminal.write('Connecting to gateway...\r\n');

      // 3. 连接 WebSocket
      _channel = WebSocketChannel.connect(uri);

      // 4. 处理输入输出

      // WebSocket -> Terminal
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            _terminal.write(data);
          } else if (data is List<int>) {
            _terminal.write(utf8.decode(data, allowMalformed: true));
          }
        },
        onError: (error) {
          if (mounted) {
            _terminal.write('\r\nConnection error: $error\r\n');
            setState(() => _isConnected = false);
          }
        },
        onDone: () {
          if (mounted) {
            _terminal.write('\r\nConnection closed.\r\n');
            setState(() => _isConnected = false);
          }
        },
      );

      // Terminal -> WebSocket
      _terminal.onOutput = (data) {
        _channel?.sink.add(data);
      };

      if (mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    } catch (e) {
      if (mounted) {
        _terminal.write('\r\nConnection failed: $e\r\n');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host?.name ?? 'Terminal'),
      ),
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              _terminal,
            ),
          ),
          VirtualKeyboard(terminal: _terminal),
        ],
      ),
    );
  }
}
