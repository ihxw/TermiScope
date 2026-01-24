import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final storageServiceProvider = Provider((ref) => StorageService());

/// 本地存储服务
class StorageService {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _serverUrlKey = 'server_url';
  static const String _rememberMeKey = 'remember_me';

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;

  StorageService()
      : _secureStorage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
        );

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ============ Token 存储 (安全存储) ============

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  Future<void> deleteRefreshToken() async {
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  Future<void> clearAuthTokens() async {
    await deleteToken();
    await deleteRefreshToken();
  }

  // ============ 服务器地址 ============

  Future<void> saveServerUrl(String url) async {
    await _prefs?.setString(_serverUrlKey, url);
  }

  String? getServerUrl() {
    return _prefs?.getString(_serverUrlKey);
  }

  // ============ 记住登录 ============

  Future<void> setRememberMe(bool value) async {
    await _prefs?.setBool(_rememberMeKey, value);
  }

  bool getRememberMe() {
    return _prefs?.getBool(_rememberMeKey) ?? false;
  }
}
