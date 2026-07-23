import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();

  static const serverUrlKey = 'server_url';
  static const tokenKey = 'token';
  static const refreshTokenKey = 'refresh_token';
  static const usernameKey = 'username';
  static const encryptedPasswordKey = 'encrypted_password';

  bool get _shouldUsePreferencesFallback {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    final host = uri.host.toLowerCase();
    return uri.scheme != 'https' &&
        host != 'localhost' &&
        host != '127.0.0.1' &&
        host != '::1';
  }

  Future<String?> read(String key) async {
    if (_shouldUsePreferencesFallback) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _storage.read(key: key);
  }

  Future<void> write(String key, String value) async {
    if (_shouldUsePreferencesFallback) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    if (_shouldUsePreferencesFallback) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    await _storage.delete(key: key);
  }

  Future<void> migrateFromPreferences() async {
    if (_shouldUsePreferencesFallback) return;

    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      serverUrlKey,
      tokenKey,
      refreshTokenKey,
      usernameKey,
      encryptedPasswordKey,
    ]) {
      final secureValue = await read(key);
      final legacyValue = prefs.getString(key);
      if ((secureValue == null || secureValue.isEmpty) &&
          legacyValue != null &&
          legacyValue.isNotEmpty) {
        await write(key, legacyValue);
      }
    }
  }
}
