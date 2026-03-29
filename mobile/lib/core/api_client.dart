import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  late Dio _dio;
  String? _baseUrl;

  // Token refresh queue for handling concurrent requests when token expires
  final List<Future<void> Function(String)> _pendingRequests = [];
  bool _isRefreshing = false;

  static ApiClient get instance => _instance;

  // Getter for base URL (for debugging)
  String get baseUrl => _baseUrl ?? AppConstants.defaultServerUrl;

  // Public method to store tokens (called from auth_service)
  Future<void> storeTokens(String token, String? refreshToken) async {
    await _setTokens(token, refreshToken);
  }

  // Public method to clear tokens (called from auth_service)
  Future<void> clearTokens() async {
    await _clearTokens();
  }

  Future<void> init() async {
    _dio = Dio();

    // Load base URL from preferences
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(AppConstants.serverUrlKey) ?? AppConstants.defaultServerUrl;

    // Set base options
    _dio.options
      ..baseUrl = _baseUrl!
      ..connectTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 30);

    // Add interceptors
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );
  }

  Future<void> _onRequest(options, handler) async {
    // Add auth token if available
    final token = await _getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    // Ensure we're using the current base URL
    final prefs = await SharedPreferences.getInstance();
    final currentBaseUrl = prefs.getString(AppConstants.serverUrlKey) ?? AppConstants.defaultServerUrl;
    if (currentBaseUrl != _baseUrl) {
      _baseUrl = currentBaseUrl;
      _dio.options.baseUrl = _baseUrl!;
    }

    handler.next(options);
  }

  Future<void> _onResponse(response, handler) async {
    // Handle successful responses
    handler.next(response);
  }

  Future<void> _onError(DioException err, handler) async {
    // Check if it's a 401 Unauthorized error
    if (err.response?.statusCode == 401) {
      final options = err.requestOptions;
      
      // If this is a refresh attempt that failed, just reject
      if (options.path.contains('/auth/refresh')) {
        await _clearTokens();
        handler.next(err);
        return;
      }

      // Attempt token refresh
      if (!_isRefreshing) {
        _isRefreshing = true;
        try {
          final newToken = await _refreshToken();
          if (newToken != null) {
            // Retry original request with new token
            options.headers['Authorization'] = 'Bearer $newToken';
            final response = await _dio.fetch(options);
            handler.resolve(response);
          } else {
            // Refresh failed, clear tokens and redirect to login
            await _clearTokens();
            handler.next(err);
          }
        } catch (e) {
          // Refresh failed, clear tokens and redirect to login
          await _clearTokens();
          handler.next(err);
        } finally {
          _isRefreshing = false;
        }
      } else {
        // Another request is already refreshing, wait for it
        final completer = Completer<Response>();
        _pendingRequests.add((newToken) async {
          options.headers['Authorization'] = 'Bearer $newToken';
          try {
            final response = await _dio.fetch(options);
            completer.complete(response);
          } catch (e) {
            completer.completeError(e);
          }
        });
        handler.resolve(await completer.future);
      }
    } else {
      handler.next(err);
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.tokenKey);
  }

  Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.refreshTokenKey);
  }

  Future<void> _setTokens(String accessToken, String? refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(AppConstants.refreshTokenKey, refreshToken);
    }
  }

  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.refreshTokenKey);
  }

  Future<String?> _refreshToken() async {
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null) {
      return null;
    }

    try {
      final response = await Dio().post(
        '$_baseUrl/api/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(
          contentType: Headers.jsonContentType,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { token: "...", refresh_token: "..." } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          print('Token refresh failed: no data in response');
          return null;
        }
        final newAccessToken = dataWrapper['token'];
        final newRefreshToken = dataWrapper['refresh_token'];

        if (newAccessToken == null || newAccessToken.isEmpty) {
          print('Token refresh failed: no token in response');
          return null;
        }

        await _setTokens(newAccessToken, newRefreshToken);
        return newAccessToken;
      }
    } catch (e) {
      print('Token refresh failed: $e');
    }

    return null;
  }

  // Generic HTTP methods
  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    return await _dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? params}) async {
    return await _dio.post(path, data: data, queryParameters: params);
  }

  Future<Response> put(String path, {dynamic data, Map<String, dynamic>? params}) async {
    return await _dio.put(path, data: data, queryParameters: params);
  }

  Future<Response> delete(String path, {Map<String, dynamic>? params}) async {
    return await _dio.delete(path, queryParameters: params);
  }

  // Authentication methods
  Future<Response> login(String username, String password, {bool remember = false}) async {
    return await post(
      AppConstants.loginEndpoint,
      data: {
        'username': username,
        'password': password,
        'remember': remember,
      },
    );
  }

  Future<Response> logout() async {
    return await post(AppConstants.logoutEndpoint);
  }

  Future<Response> checkInit() async {
    return await get(AppConstants.checkInitEndpoint);
  }

  Future<Response> initialize(String username, String password) async {
    return await post(
      AppConstants.initializeEndpoint,
      data: {'username': username, 'password': password},
    );
  }

  Future<Response> forgotPassword(String email) async {
    return await post(
      AppConstants.forgotPasswordEndpoint,
      data: {'email': email},
    );
  }

  Future<Response> resetPassword(String token, String newPassword) async {
    return await post(
      AppConstants.resetPasswordEndpoint,
      data: {
        'token': token,
        'new_password': newPassword,
      },
    );
  }

  Future<Response> getCurrentUser() async {
    return await get(AppConstants.getCurrentUserEndpoint);
  }

  Future<Response> getWSTicket() async {
    return await post(AppConstants.getWSTicketEndpoint);
  }

  Future<Response> verify2FA(String code) async {
    return await post(
      AppConstants.verify2FAEndpoint,
      data: {'code': code},
    );
  }

  Future<Response> setup2FA() async {
    return await post(AppConstants.setup2FAEndpoint);
  }

  Future<Response> verifySetup2FA(String code, String secret) async {
    return await _dio.post(
      AppConstants.verifySetup2FAEndpoint,
      data: {'code': code},
      options: Options(headers: {'X-2FA-Secret': secret}),
    );
  }

  Future<Response> disable2FA(String code) async {
    return await post(
      AppConstants.disable2FAEndpoint,
      data: {'code': code},
    );
  }

  Future<Response> regenerateBackupCodes() async {
    return await post(AppConstants.regenerateBackupCodesEndpoint);
  }

  Future<Response> getLoginHistory({int page = 1, int pageSize = 10}) async {
    return await get(
      AppConstants.getLoginHistoryEndpoint,
      params: {'page': page, 'page_size': pageSize},
    );
  }

  Future<Response> revokeSession(String jti) async {
    return await post(
      AppConstants.revokeSessionEndpoint,
      data: {'jti': jti},
    );
  }

  Future<Response> changePassword(String oldPassword, String newPassword) async {
    return await post(
      AppConstants.changePasswordEndpoint,
      data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<Response> verify2FALogin(String userId, String code, String token) async {
    return await post(
      AppConstants.verify2FALoginEndpoint,
      data: {
        'user_id': userId,
        'code': code,
        'token': token,
      },
    );
  }

  Future<Response> getTokenInfo() async {
    return await get(AppConstants.getTokenInfoEndpoint);
  }

  // Update server URL
  Future<void> updateServerUrl(String url) async {
    _baseUrl = url;
    _dio.options.baseUrl = url;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.serverUrlKey, url);
  }
}