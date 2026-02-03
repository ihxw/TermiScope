import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/services/auth_service.dart';
import '../data/models/user.dart';
import '../core/constants.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  User? _user;
  User? get user => _user;

  AuthProvider(this._authService) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    _isLoading = true;
    notifyListeners();

    final token = await _storage.read(key: AppConstants.tokenKey);
    if (token != null) {
      try {
        _user = await _authService.getCurrentUser();
        _status = AuthStatus.authenticated;
      } catch (e) {
        // If getting user fails (e.g. token expired), treat as unauthenticated
        _status = AuthStatus.unauthenticated;
        await _storage.delete(key: AppConstants.tokenKey);
      }
    } else {
      _status = AuthStatus.unauthenticated;
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authService.login(username, password);
      await _storage.write(key: AppConstants.tokenKey, value: token);

      // Update User info
      _user = await _authService.getCurrentUser();

      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _status = AuthStatus.unauthenticated;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: AppConstants.tokenKey);
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
