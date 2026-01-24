import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../services/storage_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.read(storageServiceProvider));
});

/// API 客户端封装
class ApiClient {
  late final Dio _dio;
  final StorageService _storageService;
  final Logger _logger = Logger();

  String? _baseUrl;

  ApiClient(this._storageService) {
    _dio = Dio();
    _setupInterceptors();
  }

  /// 设置服务器地址
  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _dio.options.baseUrl = '$_baseUrl/api';
  }

  /// 获取当前服务器地址
  String? get baseUrl => _baseUrl;

  /// 初始化（从存储中读取服务器地址）
  Future<void> init() async {
    final savedUrl = _storageService.getServerUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      setBaseUrl(savedUrl);
    }
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 添加 Token
          final token = await _storageService.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Content-Type'] = 'application/json';

          _logger.d('[API] ${options.method} ${options.path}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          // 统一处理响应
          final data = response.data;
          if (data is Map && data['success'] == true) {
            response.data = data['data'];
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          _logger.e('[API Error] ${error.message}');

          // 401 处理 - 尝试刷新 Token
          if (error.response?.statusCode == 401) {
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              // 重试请求
              try {
                final retryResponse = await _retry(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } catch (e) {
                handler.next(error);
                return;
              }
            }
          }

          handler.next(error);
        },
      ),
    );
  }

  Future<bool> _tryRefreshToken() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await Dio().post(
        '$_baseUrl/api/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.data['success'] == true) {
        final newToken = response.data['data']['token'];
        await _storageService.saveToken(newToken);
        return true;
      }
    } catch (e) {
      _logger.e('[API] Token refresh failed: $e');
    }
    return false;
  }

  Future<Response> _retry(RequestOptions requestOptions) async {
    final token = await _storageService.getToken();
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        'Authorization': 'Bearer $token',
      },
    );
    return _dio.request(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  // ============ HTTP 方法 ============

  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return response.data;
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data;
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data;
  }

  Future<dynamic> delete(String path, {dynamic data}) async {
    final response = await _dio.delete(path, data: data);
    return response.data;
  }
}
