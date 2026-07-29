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

  @override
  void Function(String text)? onData;
  @override
  void Function(String status)? onStatusChanged;
  @override
  void Function(String fingerprint)? onFingerprintMismatch;

  @override
  Future<bool> connect() async {
    onStatusChanged?.call('Error');
    onData?.call('\r\n[ERROR] Local network SSH is unavailable on Web.\r\n');
    return false;
  }

  @override
  void dispose() {}

  @override
  void resize(int cols, int rows) {}

  @override
  void write(String data) {}
}
