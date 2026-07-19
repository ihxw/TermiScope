class RealtimeUrl {
  static Uri build({
    required String baseUrl,
    required String path,
    required Map<String, String> query,
  }) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return Uri(
      scheme: scheme,
      userInfo: base.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: normalizedPath,
      queryParameters: query,
    );
  }
}
