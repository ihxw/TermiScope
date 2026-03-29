import 'package:flutter/foundation.dart';
import '../models/system_settings.dart';
import '../services/system_service.dart';

class SystemProvider extends ChangeNotifier {
  final SystemService _systemService;
  SystemSettings? _settings;
  bool _isLoading = false;
  String? _error;

  SystemProvider(this._systemService);

  SystemSettings? get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 获取系统设置
  Future<void> fetchSystemSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _settings = await _systemService.getSystemSettings();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 更新系统设置
  Future<bool> updateSystemSettings(UpdateSettingsRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _systemService.updateSystemSettings(request);
      _settings = await _systemService.getSystemSettings(); // Refresh settings after update
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 测试邮件发送
  Future<bool> testEmail({
    required String smtpServer,
    required String smtpPort,
    required String smtpUser,
    required String smtpPassword,
    required String smtpFrom,
    required String smtpTo,
    required bool smtpSkipVerify,
  }) async {
    try {
      await _systemService.testEmail(
        smtpServer: smtpServer,
        smtpPort: smtpPort,
        smtpUser: smtpUser,
        smtpPassword: smtpPassword,
        smtpFrom: smtpFrom,
        smtpTo: smtpTo,
        smtpSkipVerify: smtpSkipVerify,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 测试Telegram发送
  Future<bool> testTelegram({
    required String telegramBotToken,
    required String telegramChatID,
  }) async {
    try {
      await _systemService.testTelegram(
        telegramBotToken: telegramBotToken,
        telegramChatID: telegramChatID,
      );
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 备份数据库
  Future<Map<String, dynamic>?> backupDatabase({String? password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _systemService.backupDatabase(password: password);
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 恢复数据库
  Future<bool> restoreDatabase(String filename, {String? password}) async {
    try {
      await _systemService.restoreDatabase(filename, password: password);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 获取代理版本
  Future<Map<String, dynamic>?> getAgentVersion() async {
    try {
      return await _systemService.getAgentVersion();
    } catch (e) {
      _error = '获取代理版本失败';
      notifyListeners();
      return null;
    }
  }

  /// 检查更新
  Future<UpdateCheckResponse?> checkUpdate() async {
    try {
      return await _systemService.checkUpdate();
    } catch (e) {
      _error = '检查更新失败';
      notifyListeners();
      return null;
    }
  }

  /// 执行更新
  Future<bool> performUpdate(String downloadUrl) async {
    try {
      await _systemService.performUpdate(downloadUrl);
      return true;
    } catch (e) {
      _error = '执行更新失败';
      notifyListeners();
      return false;
    }
  }

  /// 获取更新状态
  Future<UpdateStatusResponse?> getUpdateStatus() async {
    try {
      return await _systemService.getUpdateStatus();
    } catch (e) {
      _error = '获取更新状态失败';
      notifyListeners();
      return null;
    }
  }
}