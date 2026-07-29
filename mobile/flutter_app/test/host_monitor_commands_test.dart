import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/utils/host_monitor_commands.dart';

void main() {
  test('builds Linux install command with secret in authorization header', () {
    final command = HostMonitorCommands.install(
      baseUrl: 'https://example.test/',
      hostId: 7,
      secret: 'monitor-secret',
      platform: 'linux',
    );

    expect(command, contains('Authorization: Bearer monitor-secret'));
    expect(command,
        contains('https://example.test/api/monitor/install?host_id=7'));
    expect(command, isNot(contains('host_id=7&secret=')));
  });

  test('builds Windows PowerShell install command', () {
    final command = HostMonitorCommands.install(
      baseUrl: 'https://example.test',
      hostId: 9,
      secret: 'windows-secret',
      platform: 'windows',
    );

    expect(command, contains(r'$headers = @{ Authorization'));
    expect(command, contains('host_id=9&os=windows'));
    expect(command, contains('termiscope-install-agent.ps1'));
  });

  test('builds uninstall command without a trailing base URL slash', () {
    final command = HostMonitorCommands.uninstall(
      baseUrl: 'https://example.test///',
      hostId: 11,
      secret: 'remove-secret',
    );

    expect(command, contains('https://example.test/api/monitor/uninstall'));
    expect(command, contains('host_id=11&secret=remove-secret'));
  });
}
