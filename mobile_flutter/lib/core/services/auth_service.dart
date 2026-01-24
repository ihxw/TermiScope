import '../api/api_client.dart';
import '../services/storage_service.dart';
import '../models/user.dart';

/// 认证服务
class AuthService {
  final ApiClient _apiClient;
  final StorageService _storageService;

  AuthService(this._apiClient, this._storageService);

  /// 登录
  Future<LoginResult> login({
    required String username,
    required String password,
    bool remember = false,
  }) async {
    final response = await _apiClient.post('/auth/login', data: {
      'username': username,
      'password': password,
      'remember': remember,
    });

    // 检查是否需要 2FA
    if (response['requires_2fa'] == true) {
      return LoginResult(
        success: false,
        requires2FA: true,
        userId: response['user_id'],
      );
    }

    // 保存 Token
    final token = response['token'];
    final refreshToken = response['refresh_token'];

    await _storageService.saveToken(token);
    if (refreshToken != null) {
      await _storageService.saveRefreshToken(refreshToken);
    }
    await _storageService.setRememberMe(remember);

    // 解析用户信息
    final user = User.fromJson(response['user']);

    return LoginResult(
      success: true,
      user: user,
      token: token,
    );
  }

  /// 2FA 验证
  Future<LoginResult> verify2FA({
    required int userId,
    required String code,
  }) async {
    final response = await _apiClient.post('/auth/verify-2fa-login', data: {
      'user_id': userId,
      'code': code,
    });

    final token = response['token'];
    final refreshToken = response['refresh_token'];

    await _storageService.saveToken(token);
    if (refreshToken != null) {
      await _storageService.saveRefreshToken(refreshToken);
    }

    final user = User.fromJson(response['user']);

    return LoginResult(
      success: true,
      user: user,
      token: token,
    );
  }

  /// 获取当前用户
  Future<User> getCurrentUser() async {
    final response = await _apiClient.get('/auth/me');
    return User.fromJson(response);
  }

  /// 登出
  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } catch (e) {
      // 忽略错误，继续清理本地数据
    }
    await _storageService.clearAuthTokens();
  }

  /// 修改密码
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  /// 获取 WebSocket 票据
  Future<String> getWSTicket() async {
    final response = await _apiClient.post('/auth/ws-ticket');
    return response['ticket'];
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    final token = await _storageService.getToken();
    return token != null && token.isNotEmpty;
  }
}

/// 登录结果
class LoginResult {
  final bool success;
  final bool requires2FA;
  final int? userId;
  final User? user;
  final String? token;

  LoginResult({
    required this.success,
    this.requires2FA = false,
    this.userId,
    this.user,
    this.token,
  });
}
