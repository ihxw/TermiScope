import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../api/api_client.dart';
import '../models/user.dart';

// ============ 基础服务 Provider ============

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ApiClient(storage);
});

final authServiceProvider = Provider<AuthService>((ref) {
  final api = ref.watch(apiClientProvider);
  final storage = ref.watch(storageServiceProvider);
  return AuthService(api, storage);
});

// ============ 认证状态 ============

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final User? user;
  final String? error;

  AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    User? user,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final StorageService _storageService;
  final ApiClient _apiClient;

  AuthNotifier(this._authService, this._storageService, this._apiClient)
      : super(AuthState());

  /// 初始化 - 检查登录状态
  Future<void> init() async {
    state = state.copyWith(isLoading: true);

    try {
      await _storageService.init();
      await _apiClient.init();

      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn) {
        final user = await _authService.getCurrentUser();
        state = AuthState(isAuthenticated: true, user: user);
      } else {
        state = AuthState(isAuthenticated: false);
      }
    } catch (e) {
      state = AuthState(isAuthenticated: false, error: e.toString());
    }
  }

  /// 登录
  Future<LoginResult> login({
    required String serverUrl,
    required String username,
    required String password,
    bool remember = false,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 保存服务器地址
      await _storageService.saveServerUrl(serverUrl);
      _apiClient.setBaseUrl(serverUrl);

      final result = await _authService.login(
        username: username,
        password: password,
        remember: remember,
      );

      if (result.success) {
        state = AuthState(isAuthenticated: true, user: result.user);
      } else {
        state = state.copyWith(isLoading: false);
      }

      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 2FA 验证
  Future<void> verify2FA({required int userId, required String code}) async {
    state = state.copyWith(isLoading: true);

    try {
      final result = await _authService.verify2FA(userId: userId, code: code);
      state = AuthState(isAuthenticated: true, user: result.user);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  /// 登出
  Future<void> logout() async {
    await _authService.logout();
    state = AuthState(isAuthenticated: false);
  }

  /// 刷新用户信息
  Future<void> refreshUser() async {
    try {
      final user = await _authService.getCurrentUser();
      state = state.copyWith(user: user);
    } catch (e) {
      // 忽略错误
    }
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(authService, storageService, apiClient);
});
