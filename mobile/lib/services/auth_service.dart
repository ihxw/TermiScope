import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/user.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient.instance;

  Future<String> login(String username, String password, {bool remember = false}) async {
    try {
      final response = await _apiClient.login(username, password, remember: remember);
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { token: "...", refresh_token: "...", user: {...} } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('Login failed: no data in response');
        }
        final token = dataWrapper['token'];
        final refreshToken = dataWrapper['refresh_token'];
        
        if (token == null || token.isEmpty) {
          throw Exception('Login failed: no token in response');
        }
        
        // Store tokens
        await _storeTokens(token, refreshToken);
        
        return token;
      } else {
        throw Exception('Login failed: Invalid response');
      }
    } catch (e) {
      if (e is DioException) {
        if (e.response?.data != null) {
          final errorData = e.response!.data as Map<String, dynamic>;
          final errorMessage = errorData['error'] ?? errorData['message'] ?? 'Login failed';
          throw Exception(errorMessage);
        }
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.logout();
    } catch (e) {
      // Even if logout API call fails, we should still clear local tokens
      print('Logout API call failed: $e');
    } finally {
      await _clearTokens();
    }
  }

  Future<User> getCurrentUser() async {
    try {
      final response = await _apiClient.getCurrentUser();
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { user info } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('Failed to get user info: no data');
        }
        return User.fromJson(dataWrapper);
      } else {
        throw Exception('Failed to get user info');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> checkInitialization() async {
    try {
      final response = await _apiClient.checkInit();
      
      print('Check init response status: ${response.statusCode}');
      print('Check init response data: ${response.data}');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { initialized: true } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        return dataWrapper?['initialized'] ?? false;
      }
      return false;
    } catch (e, stackTrace) {
      print('Error checking initialization: $e');
      print('Stack trace: $stackTrace');
      rethrow; // Rethrow to let caller handle it
    }
  }

  Future<void> initializeSystem(String username, String password) async {
    try {
      final response = await _apiClient.initialize(username, password);
      
      if (response.statusCode == 200) {
        // Auto-login after initialization
        await login(username, password);
      } else {
        throw Exception('System initialization failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      final response = await _apiClient.forgotPassword(email);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to send password reset email');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resetPassword(String token, String newPassword) async {
    try {
      final response = await _apiClient.resetPassword(token, newPassword);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to reset password');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String> getWSTicket() async {
    try {
      final response = await _apiClient.getWSTicket();
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { ticket: "..." } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        return dataWrapper?['ticket'] ?? '';
      } else {
        throw Exception('Failed to get WS ticket');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> verify2FA(String code) async {
    try {
      final response = await _apiClient.verify2FA(code);
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> setup2FA() async {
    try {
      final response = await _apiClient.setup2FA();
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { secret: "...", qr_code: "..." } }
        return data['data'] as Map<String, dynamic>? ?? {};
      } else {
        throw Exception('Failed to setup 2FA');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> verifySetup2FA(String code, String secret) async {
    try {
      final response = await _apiClient.verifySetup2FA(code, secret);
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> disable2FA(String code) async {
    try {
      final response = await _apiClient.disable2FA(code);
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> regenerateBackupCodes() async {
    try {
      final response = await _apiClient.regenerateBackupCodes();
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { backup_codes: [...] } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper?['backup_codes'] != null) {
          return (dataWrapper!['backup_codes'] as List).map((e) => e.toString()).toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getLoginHistory({int page = 1, int pageSize = 10}) async {
    try {
      final response = await _apiClient.getLoginHistory(page: page, pageSize: pageSize);
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { logs: [...], total: 100 } }
        return data['data'] as Map<String, dynamic>? ?? {};
      } else {
        throw Exception('Failed to get login history');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> revokeSession(String jti) async {
    try {
      final response = await _apiClient.revokeSession(jti);
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    try {
      final response = await _apiClient.changePassword(oldPassword, newPassword);
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<String> verify2FALogin(String userId, String code, String token) async {
    try {
      final response = await _apiClient.verify2FALogin(userId, code, token);
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { token: "...", refresh_token: "..." } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        final newToken = dataWrapper?['token'];
        final refreshToken = dataWrapper?['refresh_token'];
        
        // Store tokens
        await _storeTokens(newToken, refreshToken);
        
        return newToken ?? '';
      } else {
        throw Exception('2FA verification failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getTokenInfo() async {
    try {
      final response = await _apiClient.getTokenInfo();
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Response format: { success: true, data: { token info } }
        return data['data'] as Map<String, dynamic>? ?? {};
      } else {
        throw Exception('Failed to get token info');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Private helper methods
  Future<void> _storeTokens(String token, String? refreshToken) async {
    // Store tokens via ApiClient
    await _apiClient.storeTokens(token, refreshToken);
  }

  Future<void> _clearTokens() async {
    // Clear tokens via ApiClient
    await _apiClient.clearTokens();
  }
}