class HostMonitorCommands {
  static String install({
    required String baseUrl,
    required int hostId,
    required String secret,
    required String platform,
  }) {
    final server = _server(baseUrl);
    if (platform == 'windows') {
      return '''\$headers = @{ Authorization = "Bearer $secret" }
\$url = "$server/api/monitor/install?host_id=$hostId&os=windows"
\$scriptPath = Join-Path \$env:TEMP "termiscope-install-agent.ps1"
try {
    Invoke-WebRequest -Uri \$url -Headers \$headers -UseBasicParsing -OutFile \$scriptPath
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File \$scriptPath
} finally {
    Remove-Item -Path \$scriptPath -Force -ErrorAction SilentlyContinue
}''';
    }
    return 'curl -fsSL -H "Authorization: Bearer $secret" '
        '"$server/api/monitor/install?host_id=$hostId" | bash';
  }

  static String uninstall({
    required String baseUrl,
    required int hostId,
    required String secret,
  }) {
    final server = _server(baseUrl);
    return 'curl -fsSL '
        '"$server/api/monitor/uninstall?host_id=$hostId&secret=$secret" | bash';
  }

  static String _server(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');
}
