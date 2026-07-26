import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/services/api_service.dart';
import 'package:termiscope_mobile/services/sftp_service.dart';

void main() {
  late HttpServer server;
  late ApiService api;
  late SftpService sftp;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = ApiService()
      ..baseUrl = 'http://${server.address.host}:${server.port}'
      ..token = 'test-token';
    sftp = SftpService(api);
  });

  tearDown(() => server.close(force: true));

  test('list parses the wrapped SFTP directory response', () async {
    final requestFuture = server.first;
    final resultFuture = sftp.list('7', '/var/log');
    final request = await requestFuture;
    expect(request.uri.path, '/api/sftp/list/7');
    expect(request.uri.queryParameters['path'], '/var/log');
    expect(request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-token');
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'success': true,
      'data': {
        'cwd': '/var/log',
        'files': [
          {
            'name': 'syslog',
            'size': 42,
            'is_dir': false,
            'mod_time': '2026-07-18T00:00:00Z',
          }
        ],
      }
    }));
    await request.response.close();

    final result = await resultFuture;
    expect(result.cwd, '/var/log');
    expect(result.files.single['name'], 'syslog');
  });

  test('upload sends the Web-compatible multipart contract', () async {
    final requestFuture = server.first;
    final uploadFuture = sftp.upload(
      '3',
      '/tmp',
      SftpUploadSource.bytes(
        'hello.txt',
        Uint8List.fromList(utf8.encode('hello world')),
      ),
      overwrite: true,
    );
    final request = await requestFuture;
    expect(request.uri.path, '/api/sftp/upload/3');
    expect(request.headers.contentType?.mimeType, 'multipart/form-data');
    final body = utf8.decode(await request.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    ));
    expect(body, contains('name="path"'));
    expect(body, contains('/tmp'));
    expect(body, contains('name="file_size"'));
    expect(body, contains('name="overwrite"'));
    expect(body, contains('true'));
    expect(body, contains('filename="hello.txt"'));
    expect(body, contains('hello world'));
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"success":true,"data":{"message":"ok"}}');
    await request.response.close();

    await uploadFuture;
  });

  test('transfer consumes NDJSON progress through completion', () async {
    final events = <Map<String, dynamic>>[];
    final requestFuture = server.first;
    final transferFuture = sftp.transfer(
      sourceHostId: '1',
      destinationHostId: '2',
      sourcePath: '/src/a.txt',
      destinationPath: '/dst',
      destinationName: 'a.txt',
      onEvent: events.add,
    );
    final request = await requestFuture;
    expect(request.uri.path, '/api/sftp/transfer');
    final payload = jsonDecode(await utf8.decoder.bind(request).join());
    expect(payload['source_host_id'], '1');
    expect(payload['dest_host_id'], '2');
    expect(payload['dest_file_name'], 'a.txt');
    expect(payload['type'], 'copy');
    request.response.headers.contentType = ContentType(
      'application',
      'x-ndjson',
    );
    request.response.write('{"type":"start","total_size":10}\n');
    request.response.write(
      '{"type":"progress","transferred":5,"total":10}\n',
    );
    request.response.write('{"type":"complete"}\n');
    await request.response.close();

    await transferFuture;
    expect(events.map((event) => event['type']),
        ['start', 'progress', 'complete']);
  });

  test('paste sends the Web-compatible cut and conflict contract', () async {
    final requestFuture = server.first;
    final pasteFuture = sftp.paste(
      hostId: '9',
      source: '/src/report.txt',
      destination: '/archive',
      type: 'cut',
      destinationName: 'report (1).txt',
      overwrite: true,
    );
    final request = await requestFuture;
    expect(request.uri.path, '/api/sftp/paste/9');
    final payload = jsonDecode(await utf8.decoder.bind(request).join());
    expect(payload, {
      'source': '/src/report.txt',
      'dest': '/archive',
      'type': 'cut',
      'dest_file_name': 'report (1).txt',
      'overwrite': true,
    });
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"success":true,"data":{"message":"ok"}}');
    await request.response.close();

    await pasteFuture;
  });

  test('cancel token completes once and records cancellation', () async {
    final token = SftpCancelToken();
    var completions = 0;
    token.whenCancelled.then((_) => completions++);

    token.cancel();
    token.cancel();
    await token.whenCancelled;

    expect(token.isCancelled, isTrue);
    expect(completions, 1);
  });
}
