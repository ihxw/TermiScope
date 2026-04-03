import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import '../core/api_client.dart';
import '../models/ssh_host.dart';
import 'dart:convert';
import 'dart:typed_data';

class TerminalService {
  final ApiClient _apiClient = ApiClient.instance;
  
  SSHClient? _client;
  SSHSession? _session;
  Terminal? _terminal;

  Future<bool> connectToHost(SSHHost host, Terminal terminal) async {
    try {
      _terminal = terminal;
      
      final socket = await SSHSocket.connect(host.hostname, host.port);
      _client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => host.password ?? '',
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      _session!.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) {
        terminal.write(data);
      });
      
      _session!.stderr.cast<List<int>>().transform(utf8.decoder).listen((data) {
        terminal.write(data);
      });

      terminal.onOutput = (String data) {
        if (_session != null) {
          _session!.write(Uint8List.fromList(utf8.encode(data)));
        }
      };

      return true;
    } catch (e) {
      print('Failed to connect to host: $e');
      terminal.write('\r\n\x1b[31mFailed to connect to host: $e\x1b[0m\r\n');
      return false;
    }
  }

  void disconnect() {
    try {
      _session?.close();
      _client?.close();
      _session = null;
      _client = null;
      _terminal = null;
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  void sendCommand(String command) {
    if (_session != null) {
      _session!.write(Uint8List.fromList(utf8.encode(command)));
    }
  }

  void resizeTerminal(int cols, int rows) {
    if (_session != null) {
      _session!.resizeTerminal(cols, rows, 0, 0);
    }
  }
}