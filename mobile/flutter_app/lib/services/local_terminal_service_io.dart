import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/models.dart';
import 'terminal_connection.dart';

class LocalTerminalService implements TerminalConnection {
  LocalTerminalService({
    required this.host,
    required this.password,
    required this.privateKey,
  });

  final Host host;
  final String password;
  final String privateKey;
  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<Uint8List>? _stdoutSubscription;
  StreamSubscription<Uint8List>? _stderrSubscription;
  bool _disposed = false;

  @override
  void Function(String text)? onData;
  @override
  void Function(String status)? onStatusChanged;
  @override
  void Function(String fingerprint)? onFingerprintMismatch;

  @override
  Future<bool> connect() async {
    onStatusChanged?.call('Connecting...');
    try {
      final socket = await SSHSocket.connect(
        host.host,
        host.port,
        timeout: const Duration(seconds: 15),
      );
      if (_disposed) {
        await socket.close();
        return false;
      }

      final identities = privateKey.trim().isEmpty
          ? null
          : SSHKeyPair.fromPem(privateKey.trim());
      final client = SSHClient(
        socket,
        username: host.username,
        identities: identities,
        onPasswordRequest: password.isEmpty ? null : () => password,
        onUserInfoRequest: password.isEmpty
            ? null
            : (request) =>
                List<String>.filled(request.prompts.length, password),
        keepAliveInterval: const Duration(seconds: 15),
      );
      _client = client;
      await client.authenticated.timeout(const Duration(seconds: 20));
      final session = await client.shell(
        pty: const SSHPtyConfig(width: 80, height: 24),
      );
      if (_disposed) {
        session.close();
        client.close();
        return false;
      }
      _session = session;
      _stdoutSubscription = session.stdout.listen(_emitBytes);
      _stderrSubscription = session.stderr.listen(_emitBytes);
      session.done.then((_) {
        if (_disposed || _session != session) return;
        onStatusChanged?.call('Disconnected');
        onData?.call('\r\n[Connection Closed]\r\n');
      }, onError: (_) {
        if (_disposed || _session != session) return;
        onStatusChanged?.call('Error');
        onData?.call('\r\n[Connection Error]\r\n');
      });
      onStatusChanged?.call('Connected');
      return true;
    } catch (error) {
      if (!_disposed) {
        onStatusChanged?.call('Error');
        onData?.call('\r\n[ERROR] ${_message(error)}\r\n');
      }
      dispose();
      return false;
    }
  }

  void _emitBytes(Uint8List bytes) {
    if (!_disposed) onData?.call(utf8.decode(bytes, allowMalformed: true));
  }

  String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  @override
  void write(String data) {
    if (!_disposed && data.isNotEmpty) {
      _session?.write(Uint8List.fromList(utf8.encode(data)));
    }
  }

  @override
  void resize(int cols, int rows) {
    if (!_disposed && cols > 0 && rows > 0) {
      _session?.resizeTerminal(cols, rows);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stdoutSubscription?.cancel();
    _stderrSubscription?.cancel();
    _session?.close();
    _client?.close();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _session = null;
    _client = null;
  }
}
