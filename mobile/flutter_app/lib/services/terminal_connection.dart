abstract class TerminalConnection {
  void Function(String text)? onData;
  void Function(String status)? onStatusChanged;
  void Function(String fingerprint)? onFingerprintMismatch;

  Future<bool> connect();
  void write(String data);
  void resize(int cols, int rows);
  void dispose();
}
