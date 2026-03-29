import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/system_settings.dart';
import '../core/api_client.dart';

class SystemService {
  final ApiClient _apiClient = ApiClient.instance;

  /// 获取系统设置
  Future<SystemSettings> getSystemSettings() async {
    try {
      final response = await _apiClient.get('/api/system/settings');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { settings... } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('获取系统设置失败：无数据');
        }
        return SystemSettings.fromJson(dataWrapper);
      }
      
      throw Exception('获取系统设置失败');
    } catch (e) {
      rethrow;
    }
  }

  /// 更新系统设置
  Future<void> updateSystemSettings(UpdateSettingsRequest request) async {
    try {
      final response = await _apiClient.post('/api/system/settings', data: request.toJson());
      
      if (response.statusCode != 200) {
        throw Exception('更新系统设置失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 测试邮件发送
  Future<void> testEmail({
    required String smtpServer,
    required String smtpPort,
    required String smtpUser,
    required String smtpPassword,
    required String smtpFrom,
    required String smtpTo,
    required bool smtpSkipVerify,
  }) async {
    try {
      final response = await _apiClient.post('/api/system/settings/test-email', data: {
        'smtp_server': smtpServer,
        'smtp_port': smtpPort,
        'smtp_user': smtpUser,
        'smtp_password': smtpPassword,
        'smtp_from': smtpFrom,
        'smtp_to': smtpTo,
        'smtp_tls_skip_verify': smtpSkipVerify,
      });
      
      if (response.statusCode != 200) {
        throw Exception('测试邮件发送失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 测试 Telegram 发送
  Future<void> testTelegram({
    required String telegramBotToken,
    required String telegramChatID,
  }) async {
    try {
      final response = await _apiClient.post('/api/system/settings/test-telegram', data: {
        'telegram_bot_token': telegramBotToken,
        'telegram_chat_id': telegramChatID,
      });
      
      if (response.statusCode != 200) {
        throw Exception('测试Telegram发送失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 备份数据库
  Future<Map<String, dynamic>> backupDatabase({String? password}) async {
    try {
      final response = await _apiClient.post('/api/system/backup', data: {
        'password': password,
      });
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { filename: "...", ... } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('备份数据库失败：无数据');
        }
        return dataWrapper;
      }
      
      throw Exception('备份数据库失败');
    } catch (e) {
      rethrow;
    }
  }

  /// 下载备份文件
  Future<Response> downloadBackup(String filename) async {
    try {
      final response = await _apiClient.get('/api/system/download-backup', params: {
        'file': filename,
      });
      
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// 恢复数据库
  Future<void> restoreDatabase(String filename, {String? password}) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filename, filename: filename.split('/').last),
        'password': password,
      });
      
      final response = await _apiClient.post('/api/system/restore', data: formData);
      
      if (response.statusCode != 200) {
        throw Exception('恢复数据库失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取代理版本
  Future<Map<String, dynamic>> getAgentVersion() async {
    try {
      final response = await _apiClient.get('/api/system/agent-version');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { version: "...", ... } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('获取代理版本失败：无数据');
        }
        return dataWrapper;
      }
      
      throw Exception('获取代理版本失败');
    } catch (e) {
      rethrow;
    }
  }

  /// 检查更新
  Future<UpdateCheckResponse> checkUpdate() async {
    try {
      final response = await _apiClient.get('/api/system/check-update');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { update available... } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('检查更新失败：无数据');
        }
        return UpdateCheckResponse.fromJson(dataWrapper);
      }
      
      throw Exception('检查更新失败');
    } catch (e) {
      rethrow;
    }
  }

  /// 执行更新
  Future<void> performUpdate(String downloadUrl) async {
    try {
      final response = await _apiClient.post('/api/system/update', data: {
        'download_url': downloadUrl,
      });
      
      if (response.statusCode != 200) {
        throw Exception('执行更新失败');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// 获取更新状态
  Future<UpdateStatusResponse> getUpdateStatus() async {
    try {
      final response = await _apiClient.get('/api/system/update-status');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // Backend response format: { success: true, data: { update status... } }
        final dataWrapper = data['data'] as Map<String, dynamic>?;
        if (dataWrapper == null) {
          throw Exception('获取更新状态失败：无数据');
        }
        return UpdateStatusResponse.fromJson(dataWrapper);
      }
      
      throw Exception('获取更新状态失败');
    } catch (e) {
      rethrow;
    }
  }
}