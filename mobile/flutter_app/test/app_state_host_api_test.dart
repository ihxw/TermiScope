import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/core/storage/secure_store.dart';
import 'package:termiscope_mobile/providers/app_state.dart';
import 'package:termiscope_mobile/services/api_service.dart';

class _MemorySecureStore extends SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

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

  test('fetchHostDetails returns monitor command credentials', () async {
    final requestFuture = server.first;
    final detailsFuture = state.fetchHostDetails('7');
    final request = await requestFuture;

    expect(request.method, 'GET');
    expect(request.uri.path, '/api/ssh-hosts/7');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {
        'id': 7,
        'name': 'host-seven',
        'monitor_secret': 'secret-seven',
      },
    }));
    await request.response.close();

    final details = await detailsFuture;
    expect(details['monitor_secret'], 'secret-seven');
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

  test('deployMonitorAgent forwards the insecure confirmation flag', () async {
    final deployFuture = state.deployMonitorAgent('7', insecure: true);
    var requestCount = 0;

    await for (final request in server) {
      requestCount++;
      if (requestCount == 1) {
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/ssh-hosts/7/monitor/deploy');
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        expect(body['insecure'], isTrue);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"success":true,"data":{"message":"ok"}}');
        await request.response.close();
      } else {
        expect(request.method, 'GET');
        expect(request.uri.path, '/api/ssh-hosts');
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"success":true,"data":[]}');
        await request.response.close();
        break;
      }
    }

    expect(await deployFuture, isTrue);
  });

  test('connection test respects an offline HTTP 200 response', () async {
    final requestFuture = server.first;
    final testFuture = state.testHostConnection('7');
    final request = await requestFuture;

    expect(request.uri.path, '/api/ssh-hosts/7/test');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {
        'status': 'offline',
        'latency': 0,
        'error': 'connection refused',
      },
    }));
    await request.response.close();

    final result = await testFuture;
    expect(result['success'], isFalse);
    expect(state.hostConnectionStatus[7], isFalse);
    expect(state.hostConnectionLatency.containsKey(7), isFalse);
  });

  test('connection test stores online latency', () async {
    final requestFuture = server.first;
    final testFuture = state.testHostConnection('8');
    final request = await requestFuture;

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {'status': 'online', 'latency': 23},
    }));
    await request.response.close();

    final result = await testFuture;
    expect(result['success'], isTrue);
    expect(state.hostConnectionStatus[8], isTrue);
    expect(state.hostConnectionLatency[8], 23);
  });

  test('fetchLocalConnectCredentials uses JWT-only endpoint', () async {
    final requestFuture = server.first;
    final credentialsFuture = state.fetchLocalConnectCredentials(7);
    final request = await requestFuture;

    expect(request.method, 'GET');
    expect(request.uri.path, '/api/ssh-hosts/7/connect-credentials');
    expect(
        request.uri.queryParameters.containsKey('current_password'), isFalse);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {
        'id': 7,
        'host': '192.168.1.10',
        'port': 22,
        'username': 'root',
        'password': 'ssh-password',
        'private_key': 'private-key',
      },
    }));
    await request.response.close();

    final credentials = await credentialsFuture;
    expect(credentials['password'], 'ssh-password');
    expect(credentials['private_key'], 'private-key');
  });

  test('business 401 after successful refresh keeps the session token',
      () async {
    final api = ApiService(secureStore: _MemorySecureStore())
      ..baseUrl = 'http://${server.address.host}:${server.port}'
      ..token = 'test-token'
      ..refreshToken = 'refresh-token';
    final credentialsFuture = api.get('/api/ssh-hosts/7/connect-credentials');
    final expectation =
        expectLater(credentialsFuture, throwsA(isA<ApiException>()));

    var step = 0;
    await for (final request in server) {
      step++;
      if (step == 1) {
        expect(request.uri.path, '/api/ssh-hosts/7/connect-credentials');
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('{"error":"rejected"}');
        await request.response.close();
      } else if (step == 2) {
        expect(request.uri.path, '/api/auth/refresh');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'data': {'token': 'new-token', 'refresh_token': 'new-refresh'},
        }));
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('{"error":"rejected"}');
        await request.response.close();
        break;
      }
    }

    await expectation;
    expect(api.token, 'new-token');
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
