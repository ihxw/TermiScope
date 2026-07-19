import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_service.dart';

typedef SftpStreamFactory = Stream<List<int>> Function();

class SftpUploadSource {
  const SftpUploadSource({
    required this.name,
    required this.size,
    required this.openRead,
  });

  factory SftpUploadSource.bytes(String name, Uint8List bytes) =>
      SftpUploadSource(
        name: name,
        size: bytes.length,
        openRead: () => Stream<List<int>>.value(bytes),
      );

  final String name;
  final int size;
  final SftpStreamFactory openRead;
}

class SftpListing {
  const SftpListing({required this.cwd, required this.files});
  final String cwd;
  final List<Map<String, dynamic>> files;
}

class SftpProgress {
  const SftpProgress(
      {required this.written, required this.total, this.speed = ''});
  final int written;
  final int total;
  final String speed;
}

class SftpService {
  SftpService(this.api);
  final ApiService api;

  Future<SftpListing> list(String hostId, String path) async {
    final data = await api.get(
      '/api/sftp/list/$hostId?path=${Uri.encodeComponent(path)}',
    );
    if (data is! Map) return const SftpListing(cwd: '/', files: []);
    final rawFiles = data['files'];
    return SftpListing(
      cwd: data['cwd']?.toString() ?? path,
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : const [],
    );
  }

  Future<({List<String> history, List<String> favorites})> bookmarks(
      String hostId) async {
    final data = await api.get('/api/sftp/bookmarks/$hostId');
    final map = data is Map ? data : const {};
    List<String> strings(dynamic value) => value is List
        ? value.map((item) => item.toString()).toList()
        : <String>[];
    return (
      history: strings(map['history']),
      favorites: strings(map['favorites']),
    );
  }

  Future<void> saveBookmarks(
    String hostId,
    List<String> history,
    List<String> favorites,
  ) async {
    await api.put('/api/sftp/bookmarks/$hostId', {
      'history': history,
      'favorites': favorites,
    });
  }

  Future<void> createDirectory(String hostId, String path) =>
      api.post('/api/sftp/mkdir/$hostId', {'path': path});

  Future<void> createFile(String hostId, String path) =>
      api.post('/api/sftp/create/$hostId', {'path': path});

  Future<void> rename(
    String hostId,
    String oldPath,
    String newPath,
  ) =>
      api.post('/api/sftp/rename/$hostId', {
        'old_path': oldPath,
        'new_path': newPath,
      });

  Future<void> delete(String hostId, String path) => api.delete(
        '/api/sftp/delete/$hostId?path=${Uri.encodeComponent(path)}',
      );

  Future<Uint8List> download(String hostId, String path) => api.getBytes(
        '/api/sftp/download/$hostId',
        query: {'path': path},
      );

  Future<Uint8List> readForEditor(String hostId, String path) => api.getBytes(
        '/api/sftp/download/$hostId',
        query: {'path': path, '_t': DateTime.now().millisecondsSinceEpoch},
        headers: const {'X-Termiscope-Editor': '1'},
      );

  Future<void> upload(
    String hostId,
    String remotePath,
    SftpUploadSource source, {
    bool overwrite = false,
    ValueChanged<SftpProgress>? onProgress,
  }) async {
    final uploadId =
        'upload_${DateTime.now().microsecondsSinceEpoch}_${source.name.hashCode.abs()}';
    Timer? poller;
    var pollBusy = false;
    if (onProgress != null) {
      poller = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (pollBusy) return;
        pollBusy = true;
        try {
          final data = await api.get('/api/sftp/upload-progress/$uploadId');
          if (data is Map && data['status'] != 'not_found') {
            onProgress(SftpProgress(
              written: (data['written'] as num?)?.toInt() ?? 0,
              total: (data['total'] as num?)?.toInt() ?? source.size,
              speed: data['speed']?.toString() ?? '',
            ));
          }
        } catch (_) {
          // Progress polling is advisory; the upload response is authoritative.
        } finally {
          pollBusy = false;
        }
      });
    }

    try {
      final response = await api.sendStreamed(() async {
        final request = http.MultipartRequest(
          'POST',
          api.uri('/api/sftp/upload/$hostId'),
        )
          ..headers.addAll(api.authenticatedHeaders())
          ..fields['path'] = remotePath
          ..fields['file_size'] = '${source.size}'
          ..fields['upload_id'] = uploadId
          ..fields['overwrite'] = '$overwrite';
        request.files.add(http.MultipartFile(
          'file',
          source.openRead(),
          source.size,
          filename: source.name,
        ));
        return request;
      });
      await response.stream.drain<void>();
      onProgress?.call(SftpProgress(written: source.size, total: source.size));
    } finally {
      poller?.cancel();
    }
  }

  Future<void> transfer({
    required String sourceHostId,
    required String destinationHostId,
    required String sourcePath,
    required String destinationPath,
    required String destinationName,
    bool overwrite = false,
    ValueChanged<Map<String, dynamic>>? onEvent,
  }) async {
    final response = await api.sendStreamed(() async {
      return http.Request('POST', api.uri('/api/sftp/transfer'))
        ..headers.addAll(api.authenticatedHeaders(jsonContent: true))
        ..body = jsonEncode({
          'source_host_id': sourceHostId,
          'dest_host_id': destinationHostId,
          'source_path': sourcePath,
          'dest_path': destinationPath,
          'dest_file_name': destinationName,
          'overwrite': overwrite,
          'type': 'copy',
        });
    });

    String? error;
    var complete = false;
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      final event = Map<String, dynamic>.from(decoded);
      onEvent?.call(event);
      if (event['type'] == 'error') error = event['message']?.toString();
      if (event['type'] == 'complete') complete = true;
    }
    if (error case final message?) throw ApiException(500, message);
    if (!complete) throw const ApiException(500, 'Transfer incomplete');
  }
}

typedef ValueChanged<T> = void Function(T value);
