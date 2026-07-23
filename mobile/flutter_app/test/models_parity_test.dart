import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/models/models.dart';

void main() {
  test('Host preserves Web host fields through JSON round trip', () {
    final host = Host.fromJson({
      'id': 42,
      'name': 'production',
      'host': '10.0.0.42',
      'port': 2222,
      'username': 'deploy',
      'auth_type': 'key',
      'remote_shell': 'bash',
      'os_type': 'linux',
      'fingerprint': 'SHA256:test',
      'group_name': 'prod',
      'tags': 'edge,primary',
      'description': 'Primary edge host',
      'host_type': 'control_monitor',
      'monitor_enabled': true,
      'status': 'online',
      'agent_version': 'v1.2.3',
      'notify_offline_enabled': false,
      'notify_traffic_enabled': true,
      'notify_offline_threshold': 5,
      'notify_traffic_threshold': 85,
      'notify_channels': 'email',
      'deleted_at': {
        'Time': '2026-07-18T10:00:00Z',
        'Valid': true,
      },
    });

    expect(host.authType, 'key');
    expect(host.remoteShell, 'bash');
    expect(host.groupName, 'prod');
    expect(host.description, 'Primary edge host');
    expect(host.notifyOfflineEnabled, isFalse);
    expect(host.deletedAt, DateTime.utc(2026, 7, 18, 10));

    final json = host.toJson();
    expect(json['auth_type'], 'key');
    expect(json['remote_shell'], 'bash');
    expect(json['os_type'], 'linux');
    expect(json['group_name'], 'prod');
    expect(json['description'], 'Primary edge host');
    expect(json['notify_offline_threshold'], 5);
  });

  test('legacy ssh host type normalizes to control_monitor', () {
    final host = Host.fromJson({
      'id': 1,
      'name': 'legacy',
      'host': '127.0.0.1',
      'host_type': 'ssh',
    });

    expect(host.hostType, 'control_monitor');
  });

  test('command template keeps auto_enter behavior', () {
    final template = CommandTemplate.fromJson({
      'id': 7,
      'name': 'uptime',
      'command': 'uptime',
      'auto_enter': true,
    });

    expect(template.autoEnter, isTrue);
    expect(template.toJson()['auto_enter'], isTrue);
  });
}
