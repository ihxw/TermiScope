import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/providers/app_state.dart';

void main() {
  late HttpServer server;
  late AppState state;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    state = AppState();
    state.apiService
      ..baseUrl = 'http://${server.address.host}:${server.port}'
      ..token = 'test-token';
  });

  tearDown(() => server.close(force: true));

  test('fetchHosts requests include_deleted and parses deleted records',
      () async {
    final requestFuture = server.first;
    final fetchFuture = state.fetchHosts(includeDeleted: true);
    final request = await requestFuture;

    expect(request.uri.path, '/api/ssh-hosts');
    expect(request.uri.queryParameters['include_deleted'], 'true');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': [
        {
          'id': 9,
          'name': 'deleted',
          'host': '10.0.0.9',
          'deleted_at': '2026-07-18T10:00:00Z',
        }
      ],
    }));
    await request.response.close();
    await fetchFuture;

    expect(state.hosts.single.deletedAt, isNotNull);
  });

  test('permanent delete uses Web-compatible endpoint', () async {
    final requestFuture = server.first;
    final deleteFuture = state.permanentlyDeleteHost('9');
    final request = await requestFuture;

    expect(request.method, 'DELETE');
    expect(request.uri.path, '/api/ssh-hosts/9/permanent');
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"success":true,"data":{"message":"ok"}}');
    await request.response.close();

    expect(await deleteFuture, isTrue);
  });

  test('revealHostCredentials sends current password and returns credentials',
      () async {
    final requestFuture = server.first;
    final revealFuture = state.revealHostCredentials(7, 'p@ss word');
    final request = await requestFuture;

    expect(request.method, 'GET');
    expect(request.uri.path, '/api/ssh-hosts/7');
    expect(request.uri.queryParameters['reveal'], 'true');
    expect(request.uri.queryParameters['current_password'], 'p@ss word');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {
        'id': 7,
        'password': 'ssh-password',
        'private_key': 'private-key',
      },
    }));
    await request.response.close();

    final credentials = await revealFuture;
    expect(credentials['password'], 'ssh-password');
    expect(credentials['private_key'], 'private-key');
  });

  test('monitor disconnect marks cached metrics offline', () {
    state.updateMonitorData({
      'host_id': 3,
      'status': 'online',
      'net_rx_rate': 12,
      'net_tx_rate': 34,
    });

    state.markAllMonitorOffline();

    expect(state.monitorData['3']['_offline'], isTrue);
    expect(state.monitorData['3']['status'], 'offline');
    expect(state.monitorData['3']['net_rx_rate'], 0);

    state.updateMonitorData({
      'host_id': 3,
      'status': 'online',
      'net_rx_rate': 99,
    });
    expect(state.monitorData['3']['_offline'], isFalse);
    expect(state.monitorData['3']['status'], 'online');
  });
}
