import 'dart:convert';
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

  Future<dynamic> get(String endpoint) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => http.get(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
        ));
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => http.post(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => http.put(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<dynamic> delete(String endpoint) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      throw Exception('Server URL not set');
    }
    return _sendWithRefresh(() => http.delete(
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

  Future<bool> _refreshAccessToken() async {
    final currentRefreshToken = refreshToken;
    if (baseUrl == null ||
        baseUrl!.isEmpty ||
        currentRefreshToken == null ||
        currentRefreshToken.isEmpty) {
      return false;
    }

    final response = await http.post(
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

    final body = _tryDecodeJson(response.body);
    final message = body is Map
        ? body['message'] ?? body['error'] ?? 'Failed: ${response.statusCode}'
        : 'Failed: ${response.statusCode}';
    throw Exception(message);
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

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}
