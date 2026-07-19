import 'dart:io';

Future<bool> probeLocalNetworkHost(String host, int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    return true;
  } catch (_) {
    return false;
  } finally {
    socket?.destroy();
  }
}
