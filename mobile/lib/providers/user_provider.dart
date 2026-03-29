import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/user_service.dart';

class UserProvider extends ChangeNotifier {
  final UserService _userService;
  List<User> _users = [];
  bool _isLoading = false;
  String? _error;

  UserProvider(this._userService);

  List<User> get users => _users;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fetch all users
  Future<void> fetchUsers({int page = 1, int pageSize = 10, String search = ''}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _users = await _userService.getUsers(page: page, pageSize: pageSize, search: search);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new user
  Future<bool> createUser(User userData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newUser = await _userService.createUser(userData);
      _users.add(newUser);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update an existing user
  Future<bool> updateUser(int userId, User userData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedUser = await _userService.updateUser(userId, userData);
      final index = _users.indexWhere((user) => user.id == userId);
      if (index != -1) {
        _users[index] = updatedUser;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Delete a user
  Future<bool> deleteUser(int userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _userService.deleteUser(userId);
      if (success) {
        _users.removeWhere((user) => user.id == userId);
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Toggle 2FA for a user
  Future<bool> toggle2FA(int userId, bool enable) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _userService.toggle2FA(userId, enable);
      if (success) {
        final index = _users.indexWhere((user) => user.id == userId);
        if (index != -1) {
          _users[index] = _users[index].copyWith(
            twoFactorEnabled: enable,
          );
        }
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Get a user by ID
  User? getUserById(int userId) {
    return _users.firstWhere((user) => user.id == userId, orElse: () => _users.first);
  }

  // Refresh the user list
  Future<void> refreshUsers() async {
    await fetchUsers();
  }
}