import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/storage/secure_store.dart';
import '../utils/encryption.dart';

class ApiService {
  final SecureStore secureStore;
  String? baseUrl;
  String? token;
  String? refreshToken;
  String? _encryptedPassword;
  String? savedUsername;
  final http.Client _client = http.Client();

  ApiService({SecureStore? secureStore})
      : secureStore = secureStore ?? SecureStore();

  Future<void> init() async {
    await secureStore.migrateFromPreferences();
    baseUrl = await secureStore.read(SecureStore.serverUrlKey) ?? '';
    token = await secureStore.read(SecureStore.tokenKey) ?? '';
    refreshToken = await secureStore.read(SecureStore.refreshTokenKey) ?? '';
    savedUsername = await secureStore.read(SecureStore.usernameKey) ?? '';
    _encryptedPassword =
        await secureStore.read(SecureStore.encryptedPasswordKey);
  }

  Future<void> saveSettings(
    String url,
    String newToken, {
    String? newRefreshToken,
    String? username,
    String? password,
  }) async {
    await secureStore.write(SecureStore.serverUrlKey, url);
    await secureStore.write(SecureStore.tokenKey, newToken);
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      await secureStore.write(SecureStore.refreshTokenKey, newRefreshToken);
      refreshToken = newRefreshToken;
    }
    if (username != null) {
      await secureStore.write(SecureStore.usernameKey, username);
      savedUsername = username;
    }
    if (password != null && password.isNotEmpty) {
      final encrypted = EncryptionUtil.encrypt(password);
      await secureStore.write(SecureStore.encryptedPasswordKey, encrypted);
      _encryptedPassword = encrypted;
    }
    baseUrl = url;
    token = newToken;
  }

  Future<void> logout() async {
    try {
      await post('/api/auth/logout', {});
    } catch (_) {
      // Ignore errors during logout
    }
    await secureStore.delete(SecureStore.tokenKey);
    await secureStore.delete(SecureStore.refreshTokenKey);
    await secureStore.delete(SecureStore.encryptedPasswordKey);
    _encryptedPassword = null;
    token = '';
    refreshToken = '';
  }

  String? get decryptedPassword {
    if (_encryptedPassword == null) return null;
    return EncryptionUtil.decrypt(_encryptedPassword!);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  Uri uri(String endpoint, [Map<String, dynamic>? query]) {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw StateError('Server URL not set');
    }
    final resolved = Uri.parse('$baseUrl$endpoint');
    if (query == null || query.isEmpty) return resolved;
    return resolved.replace(
      queryParameters: query.map((key, value) => MapEntry(key, '$value')),
    );
  }

  Map<String, String> authenticatedHeaders({
    bool jsonContent = false,
    Map<String, String>? extra,
  }) =>
      {
        if (jsonContent) 'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
        ...?extra,
      };

  Future<dynamic> get(String endpoint) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => _client.get(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
        ));
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => _client.post(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => _client.put(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> delete(String endpoint) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => _client.delete(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
        ));
  }

  dynamic _unauthorizedError(http.Response response) =>
      UnauthorizedException('${response.statusCode} - ${response.body}');

  Future<dynamic> _sendWithRefresh(
      Future<http.Response> Function() send) async {
    final response = await send();
    if (response.statusCode != 401) {
      return _processResponse(response);
    }

    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      return _processResponse(response);
    }

    return _processResponse(await send());
  }

  /// Sends a replayable streaming request and refreshes authentication once.
  /// The request factory is called again after a 401, so upload streams must be
  /// reopenable.
  Future<http.StreamedResponse> sendStreamed(
    Future<http.BaseRequest> Function() requestFactory,
  ) async {
    Future<http.StreamedResponse> send() async =>
        _client.send(await requestFactory());

    var response = await send();
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      if (await _refreshAccessToken()) {
        response = await send();
      } else {
        await secureStore.delete(SecureStore.tokenKey);
        token = '';
        throw UnauthorizedException('401 - session expired');
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final body = await response.stream.bytesToString();
    throw _responseException(response.statusCode, body);
  }

  Future<Uint8List> getBytes(
    String endpoint, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final response = await sendStreamed(() async {
      return http.Request('GET', uri(endpoint, query))
        ..headers.addAll(authenticatedHeaders(extra: headers));
    });
    final bytes = await response.stream.toBytes();
    return Uint8List.fromList(bytes);
  }

  Future<bool> _refreshAccessToken() async {
    final currentRefreshToken = refreshToken;
    if (baseUrl == null ||
        baseUrl!.isEmpty ||
        currentRefreshToken == null ||
        currentRefreshToken.isEmpty) {
      return false;
    }

    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': currentRefreshToken}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }

    final data = _decodeResponseData(response);
    if (data is! Map) return false;

    final newToken = data['token']?.toString();
    final newRefreshToken = data['refresh_token']?.toString();
    if (newToken == null || newToken.isEmpty) return false;

    token = newToken;
    await secureStore.write(SecureStore.tokenKey, newToken);
    if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
      refreshToken = newRefreshToken;
      await secureStore.write(SecureStore.refreshTokenKey, newRefreshToken);
    }
    return true;
  }

  Future<dynamic> _processResponse(http.Response response) async {
    if (response.statusCode == 401) {
      await secureStore.delete(SecureStore.tokenKey);
      token = '';
      throw _unauthorizedError(response);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeResponseData(response);
    }

    throw _responseException(response.statusCode, response.body);
  }

  ApiException _responseException(int statusCode, String body) {
    final decoded = _tryDecodeJson(body);
    final message = decoded is Map
        ? decoded['message'] ?? decoded['error'] ?? 'Failed: $statusCode'
        : (body.trim().isEmpty ? 'Failed: $statusCode' : body.trim());
    return ApiException(statusCode, '$message');
  }

  dynamic _decodeResponseData(http.Response response) {
    final jsonResponse = _tryDecodeJson(response.body);
    if (jsonResponse is Map && jsonResponse['success'] == true) {
      return jsonResponse['data'];
    }
    return jsonResponse;
  }

  dynamic _tryDecodeJson(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}
