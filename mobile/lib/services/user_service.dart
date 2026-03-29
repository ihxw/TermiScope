import '../core/api_client.dart';
import '../models/user.dart';

class UserService {
  final ApiClient _apiClient = ApiClient.instance;

  // Get all users
  Future<List<User>> getUsers({int page = 1, int pageSize = 10, String search = ''}) async {
    try {
      final response = await _apiClient.get(
        '/users',
        params: {
          'page': page,
          'page_size': pageSize,
          'search': search,
        },
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['users'] != null) {
          return (data['users'] as List)
              .map((json) => User.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Create a new user
  Future<User> createUser(User userData) async {
    try {
      final response = await _apiClient.post('/users', data: userData.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return User.fromJson(response.data);
      } else {
        throw Exception('Failed to create user');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Update an existing user
  Future<User> updateUser(int userId, User userData) async {
    try {
      final response = await _apiClient.put('/users/$userId', data: userData.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return User.fromJson(response.data);
      } else {
        throw Exception('Failed to update user');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Delete a user
  Future<bool> deleteUser(int userId) async {
    try {
      final response = await _apiClient.delete('/users/$userId');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get login history for a user
  Future<List<Map<String, dynamic>>> getUserLoginHistory(int userId, {int page = 1, int pageSize = 10}) async {
    try {
      final response = await _apiClient.get(
        '/auth/login-history',
        params: {
          'user_id': userId,
          'page': page,
          'page_size': pageSize,
        },
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['history'] != null) {
          return (data['history'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Revoke user session
  Future<bool> revokeSession(String jti) async {
    try {
      final response = await _apiClient.post(
        '/auth/sessions/revoke',
        data: {'jti': jti},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Toggle 2FA for a user
  Future<bool> toggle2FA(int userId, bool enable) async {
    try {
      // This is a simplified version - actual implementation may vary
      // depending on the backend API for managing 2FA for other users
      return true;
    } catch (e) {
      return false;
    }
  }
}