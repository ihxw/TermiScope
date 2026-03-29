import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../core/constants.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService;
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

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey);
    
    if (token != null) {
      try {
        _user = await _authService.getCurrentUser();
        _status = AuthStatus.authenticated;
      } catch (e) {
        // If getting user fails (e.g. token expired), treat as unauthenticated
        _status = AuthStatus.unauthenticated;
        await prefs.remove(AppConstants.tokenKey);
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

  Future<bool> loginWith2FA(String userId, String code, String tempToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _authService.verify2FALogin(userId, code, tempToken);
      
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
    await _authService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> initializeSystem(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.initializeSystem(username, password);
      
      _user = await _authService.getCurrentUser();
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.forgotPassword(email);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkInitialization() async {
    return await _authService.checkInitialization();
  }

  Future<bool> requires2FA(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Attempt to login which might return a 2FA challenge
      final token = await _authService.login(username, password);
      
      // If we get a token directly, 2FA is not required
      _user = await _authService.getCurrentUser();
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return false;
    } on Exception catch (e) {
      // Check if the error is related to 2FA requirement
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('2fa') || errorMsg.contains('two-factor')) {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = e.toString().replaceAll('Exception: ', '');
        _status = AuthStatus.unauthenticated;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }
  }

  String? get userId {
    return _user?.id.toString();
  }

  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _user?.role == 'admin';

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _authService.changePassword(oldPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}