import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppState extends ChangeNotifier {
  final ApiService apiService = ApiService();
  bool isInitialized = false;
  bool systemInitialized = true;
  List<Host> hosts = [];
  Map<String, dynamic> monitorData = {}; // host_id -> monitor info

  // Terminal Tab Management
  List<Map<String, dynamic>> activeTerminals = [];
  String? activeTabId;

  // Settings
  double terminalFontSize = 14.0;
  String terminalFontFamily = 'TermiScope Mono';
  String terminalTheme = 'auto';
  bool useQuickToggle = false;
  ThemeMode themeMode = ThemeMode.light;
  String locale = 'zh';

  // Profile
  UserProfile? profile;
  String backendVersion = '...';
  bool updateAvailable = false;
  Map<String, dynamic>? updateInfo;
  bool updateLoading = false;
  String serverUpdateStatus = '';
  String serverUpdateError = '';

  // Command Templates
  List<CommandTemplate> commandTemplates = [];

  // Connection History (paginated)
  List<ConnectionLog> connectionLogs = [];
  int connectionLogsTotal = 0;
  int connectionLogsPage = 1;
  static const int _logsPageSize = 20;

  // Login Sessions
  List<LoginSession> loginSessions = [];

  // 2FA state
  String? twoFactorTempToken;
  int? twoFactorUserId;

  Future<void> init() async {
    await apiService.init();
    // Load saved settings
    final prefs = await SharedPreferences.getInstance();
    terminalFontSize = prefs.getDouble('terminal_font_size') ?? 14.0;
    terminalFontFamily = _normalizeTerminalFontFamily(
      prefs.getString('terminal_font_family') ?? 'TermiScope Mono',
    );
    terminalTheme = prefs.getString('terminal_theme') ?? 'auto';
    useQuickToggle = prefs.getBool('use_quick_toggle') ?? false;

    // Load saved theme
    final themeStr = prefs.getString('theme_mode') ?? 'light';
    if (themeStr == 'light') {
      themeMode = ThemeMode.light;
    } else if (themeStr == 'system') {
      themeMode = ThemeMode.system;
    } else {
      themeMode = ThemeMode.dark;
    }

    // Load saved locale
    locale = prefs.getString('locale') ?? 'zh';

    // Load saved terminals
    await _loadSavedTerminals();
    await checkInit();
    isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadSavedTerminals() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('active_terminals');
    if (saved != null) {
      try {
        final List decoded = jsonDecode(saved);
        activeTerminals = decoded.cast<Map<String, dynamic>>();
        if (activeTerminals.isNotEmpty) {
          activeTabId = activeTerminals.first['tabId'];
        }
      } catch (e) {
        print('Load saved terminals error: $e');
      }
    }
  }

  Future<void> _saveTerminals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_terminals', jsonEncode(activeTerminals));
  }

  // ── Authentication ──

  Future<bool> checkInit() async {
    try {
      final data = await apiService.get('/api/auth/check-init');
      if (data is Map) {
        systemInitialized = data['initialized'] == true;
      } else {
        systemInitialized = true;
      }
    } catch (e) {
      print('Check init error: $e');
      systemInitialized = true;
    }
    notifyListeners();
    return systemInitialized;
  }

  String _formatLoginError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    if (lower.contains('certificate_verify_failed')) {
      if (lower.contains('not yet valid')) {
        return locale == 'zh'
            ? 'HTTPS 证书尚未生效。请检查手机系统时间/时区是否正确，并确认服务器证书的生效时间没有晚于当前时间。'
            : 'The HTTPS certificate is not valid yet. Check the phone date/time and timezone, and verify that the server certificate is already valid.';
      }
      if (lower.contains('has expired')) {
        return locale == 'zh'
            ? 'HTTPS 证书已过期。请更新服务器证书后重试。'
            : 'The HTTPS certificate has expired. Renew the server certificate and try again.';
      }
      return locale == 'zh'
          ? 'HTTPS 证书校验失败。请确认服务器地址、证书域名和证书链配置正确。'
          : 'HTTPS certificate verification failed. Check the server URL, certificate hostname, and certificate chain.';
    }

    return raw;
  }

  Future<Map<String, dynamic>> login(
      String url, String username, String password, bool rememberMe) async {
    apiService.baseUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    try {
      final data = await apiService.post('/api/auth/login', {
        'username': username,
        'password': password,
        'remember': true,
      });

      if (data is Map && data['requires_2fa'] == true) {
        twoFactorTempToken = data['temp_token'];
        twoFactorUserId = data['user_id'];
        return {'requires_2fa': true};
      }

      final token = data['token'];
      if (token != null) {
        await apiService.saveSettings(
          apiService.baseUrl!,
          token,
          newRefreshToken: data['refresh_token']?.toString(),
          username: rememberMe ? username : null,
          password: rememberMe ? password : null,
        );
        await fetchHosts();
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      print('Login error: $e');
      return {'success': false, 'error': _formatLoginError(e)};
    }
  }

  Future<Map<String, dynamic>> initializeSystem(
      String url, String username, String password) async {
    apiService.baseUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    try {
      final data = await apiService.post('/api/auth/initialize', {
        'username': username,
        'password': password,
      });
      final token = data['token'];
      if (token != null) {
        await apiService.saveSettings(
          apiService.baseUrl!,
          token.toString(),
          newRefreshToken: data['refresh_token']?.toString(),
          username: username,
        );
        systemInitialized = true;
        await fetchProfile();
        await fetchHosts();
        notifyListeners();
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      print('Initialize system error: $e');
      return {'success': false, 'error': _formatLoginError(e)};
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String url, String email) async {
    apiService.baseUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    try {
      final data = await apiService.post('/api/auth/forgot-password', {
        'email': email,
      });
      return {
        'success': true,
        'message': data is Map ? data['message'] : null,
      };
    } catch (e) {
      print('Forgot password error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String url, String token, String password) async {
    apiService.baseUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    try {
      final data = await apiService.post('/api/auth/reset-password', {
        'token': token,
        'password': password,
      });
      return {
        'success': true,
        'message': data is Map ? data['message'] : null,
      };
    } catch (e) {
      print('Reset password error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> verify2faLogin(String code) async {
    if (twoFactorTempToken == null || twoFactorUserId == null) return false;
    try {
      final data = await apiService.post('/api/auth/verify-2fa-login', {
        'user_id': twoFactorUserId,
        'code': code,
        'token': twoFactorTempToken,
      });
      final token = data['token'];
      if (token != null) {
        await apiService.saveSettings(
          apiService.baseUrl!,
          token,
          newRefreshToken: data['refresh_token']?.toString(),
        );
        await fetchHosts();
        twoFactorTempToken = null;
        twoFactorUserId = null;
        return true;
      }
      return false;
    } catch (e) {
      print('2FA verify error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await apiService.logout();
    hosts = [];
    monitorData = {};
    profile = null;
    commandTemplates = [];
    connectionLogs = [];
    loginSessions = [];
    notifyListeners();
  }

  // ── Profile ──

  Future<void> fetchProfile() async {
    try {
      final data = await apiService.get('/api/auth/me');
      if (data != null) {
        profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
        notifyListeners();
      }
    } catch (e) {
      print('Fetch profile error: $e');
    }
  }

  Future<void> fetchSystemInfo() async {
    try {
      final data = await apiService.get('/api/system/info');
      if (data is Map) {
        backendVersion = data['version']?.toString() ?? 'unknown';
      } else {
        backendVersion = 'unknown';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Fetch system info error: $e');
      backendVersion = 'unknown';
      notifyListeners();
    }
  }

  Future<void> checkForUpdates() async {
    try {
      final data = await apiService.post('/api/system/check-update', {});
      if (data is Map && data['update_available'] == true) {
        updateAvailable = true;
        updateInfo = Map<String, dynamic>.from(data);
      } else {
        updateAvailable = false;
        updateInfo = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Check update error: $e');
    }
  }

  Future<void> performServerUpdate() async {
    final downloadUrl = updateInfo?['download_url']?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      serverUpdateStatus = 'error';
      serverUpdateError = 'Missing download URL';
      notifyListeners();
      return;
    }

    updateLoading = true;
    serverUpdateStatus = 'starting';
    serverUpdateError = '';
    notifyListeners();

    try {
      await apiService.post('/api/system/upgrade', {
        'download_url': downloadUrl,
      });
    } catch (e) {
      serverUpdateStatus = 'error';
      serverUpdateError = e.toString();
    } finally {
      updateLoading = false;
      notifyListeners();
    }
  }

  Future<void> pollUpdateStatus() async {
    try {
      final data = await apiService.get(
        '/api/system/update-status?_t=${DateTime.now().millisecondsSinceEpoch}',
      );
      if (data is Map) {
        final status = data['status']?.toString() ?? '';
        serverUpdateStatus = status.isEmpty ? 'finished' : status;
        serverUpdateError = data['error']?.toString() ?? '';
        if (serverUpdateStatus == 'finished') {
          await fetchSystemInfo();
          updateAvailable = false;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Poll update status error: $e');
      if (serverUpdateStatus != 'finished' && serverUpdateStatus != 'error') {
        serverUpdateStatus = 'restarting';
        notifyListeners();
      }
    }
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    try {
      await apiService.post('/api/auth/change-password', {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      await apiService.logout();
      hosts = [];
      monitorData = {};
      profile = null;
      commandTemplates = [];
      loginSessions = [];
      notifyListeners();
      return true;
    } catch (e) {
      print('Change password error: $e');
      return false;
    }
  }

  Future<void> fetchLoginHistory() async {
    try {
      final data =
          await apiService.get('/api/auth/login-history?page=1&page_size=20');
      if (data is Map) {
        final logList = data['data'] as List? ?? [];
        loginSessions = logList
            .map((e) => LoginSession.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      print('Fetch login history error: $e');
    }
  }

  Future<bool> revokeSession(String jti) async {
    try {
      await apiService.post('/api/auth/sessions/revoke', {'jti': jti});
      await fetchLoginHistory();
      return true;
    } catch (e) {
      print('Revoke session error: $e');
      return false;
    }
  }

  // ── Hosts ──

  Future<void> fetchHosts() async {
    try {
      final data = await apiService.get('/api/ssh-hosts');
      if (data is List) {
        hosts = data
            .map((e) => Host.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      print('Fetch hosts error: $e');
      if (e is UnauthorizedException) {
        await logout();
      }
    }
  }

  Future<bool> addHost(Map<String, dynamic> host) async {
    try {
      final result = await apiService.post('/api/ssh-hosts', host);
      if (result != null) {
        await fetchHosts();
        return true;
      }
      return false;
    } catch (e) {
      print('Add host error: $e');
      return false;
    }
  }

  Future<bool> updateHost(String id, Map<String, dynamic> updates) async {
    try {
      final result = await apiService.put('/api/ssh-hosts/$id', updates);
      if (result != null) {
        await fetchHosts();
        return true;
      }
      return false;
    } catch (e) {
      print('Update host error: $e');
      return false;
    }
  }

  Future<bool> deleteHost(String id) async {
    try {
      await apiService.delete('/api/ssh-hosts/$id');
      await fetchHosts();
      return true;
    } catch (e) {
      print('Delete host error: $e');
      return false;
    }
  }

  Future<bool> reorderHosts(List<int> ids) async {
    try {
      await apiService.put('/api/ssh-hosts/reorder', {'device_ids': ids});
      final idIndices = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      hosts.sort((a, b) {
        final idxA = idIndices[a.id];
        final idxB = idIndices[b.id];
        if (idxA == null && idxB == null) return 0;
        if (idxA == null) return 1;
        if (idxB == null) return -1;
        return idxA.compareTo(idxB);
      });
      notifyListeners();
      return true;
    } catch (e) {
      print('Reorder hosts error: $e');
      return false;
    }
  }


  /// Test SSH connection to a host
  Future<Map<String, dynamic>> testHostConnection(String id) async {
    try {
      final result = await apiService.post('/api/ssh-hosts/$id/test', {});
      return {
        'success': true,
        'message': result is Map ? result['message'] : 'Connection successful'
      };
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      return {'success': false, 'message': msg};
    }
  }

  /// Deploy monitor agent to a host
  Future<bool> deployMonitorAgent(String id) async {
    try {
      await apiService.post('/api/ssh-hosts/$id/monitor/deploy', {});
      await fetchHosts();
      return true;
    } catch (e) {
      print('Deploy agent error: $e');
      return false;
    }
  }

  /// Stop monitor agent on a host
  Future<bool> stopMonitorAgent(String id) async {
    try {
      await apiService.post('/api/ssh-hosts/$id/monitor/stop', {});
      await fetchHosts();
      return true;
    } catch (e) {
      print('Stop agent error: $e');
      return false;
    }
  }

  // ── WebSocket Ticket ──

  Future<String?> getTicket() async {
    try {
      final data = await apiService.post('/api/auth/ws-ticket', {});
      return data['ticket'];
    } catch (e) {
      print('Get ticket error: $e');
      if (e is UnauthorizedException) {
        await logout();
      }
      return null;
    }
  }

  // ── Monitor ──

  void updateMonitorData(Map<String, dynamic> update) {
    final hostId = update['host_id'].toString();
    if (monitorData.containsKey(hostId)) {
      monitorData[hostId] = {...monitorData[hostId], ...update};
    } else {
      monitorData[hostId] = update;
    }
    notifyListeners();
  }

  // ── Command Templates ──

  Future<void> fetchCommandTemplates() async {
    try {
      final data = await apiService.get('/api/command-templates');
      if (data is List) {
        commandTemplates = data
            .map((e) => CommandTemplate.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      print('Fetch command templates error: $e');
    }
  }

  Future<bool> createCommandTemplate(
      String name, String command, String description) async {
    try {
      await apiService.post('/api/command-templates', {
        'name': name,
        'command': command,
        'description': description,
      });
      await fetchCommandTemplates();
      return true;
    } catch (e) {
      print('Create command template error: $e');
      return false;
    }
  }

  Future<bool> updateCommandTemplate(
      int id, String name, String command, String description) async {
    try {
      await apiService.put('/api/command-templates/$id', {
        'name': name,
        'command': command,
        'description': description,
      });
      await fetchCommandTemplates();
      return true;
    } catch (e) {
      print('Update command template error: $e');
      return false;
    }
  }

  Future<bool> deleteCommandTemplate(int id) async {
    try {
      await apiService.delete('/api/command-templates/$id');
      await fetchCommandTemplates();
      return true;
    } catch (e) {
      print('Delete command template error: $e');
      return false;
    }
  }

  // ── Connection History ──

  Future<void> fetchConnectionLogs({int? hostId}) async {
    try {
      var endpoint =
          '/api/connection-logs?page=$connectionLogsPage&page_size=$_logsPageSize';
      if (hostId != null) endpoint += '&host_id=$hostId';
      final data = await apiService.get(endpoint);
      if (data is Map) {
        final logList = data['data'] as List? ?? [];
        connectionLogs = logList
            .map((e) => ConnectionLog.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        connectionLogsTotal = data['pagination']?['total'] ?? 0;
        notifyListeners();
      }
    } catch (e) {
      print('Fetch connection logs error: $e');
    }
  }

  // ── Terminal Tab Helpers ──

  void addTerminal(Host host, {bool record = false}) {
    final hostIdVal = host.id;
    if (hostIdVal == 0) {
      final String id = '${hostIdVal}_${DateTime.now().millisecondsSinceEpoch}';
      activeTerminals.add({
        'tabId': id,
        'hostId': hostIdVal,
        'name': host.name,
        'record': record,
      });
      activeTabId = id;
      notifyListeners();
      return;
    }

    final existing = activeTerminals.firstWhere(
      (t) => t['hostId'].toString() == hostIdVal.toString(),
      orElse: () => {},
    );
    if (existing.isNotEmpty) {
      activeTabId = existing['tabId'];
      notifyListeners();
      return;
    }

    final String id = '${hostIdVal}_${DateTime.now().millisecondsSinceEpoch}';
    activeTerminals.add({
      'tabId': id,
      'hostId': hostIdVal,
      'name': host.name,
      'record': record,
    });
    activeTabId = id;
    notifyListeners();
  }

  void removeTerminal(String tabId) {
    activeTerminals.removeWhere((t) => t['tabId'] == tabId);
    if (activeTabId == tabId) {
      activeTabId =
          activeTerminals.isNotEmpty ? activeTerminals.last['tabId'] : null;
    }
    _saveTerminals();
    notifyListeners();
  }

  void setActiveTabId(String? tabId) {
    activeTabId = tabId;
    notifyListeners();
  }

  // ── Settings ──

  Future<void> updateTerminalFontSize(double size) async {
    terminalFontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_font_size', size);
    notifyListeners();
  }

  Future<void> updateTerminalFontFamily(String family) async {
    terminalFontFamily = _normalizeTerminalFontFamily(family);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_font_family', terminalFontFamily);
    notifyListeners();
  }

  String _normalizeTerminalFontFamily(String family) {
    final value = family.trim();
    if (value.contains('JetBrains Mono') ||
        value == 'TermiScope Mono' ||
        value.isEmpty) {
      return 'TermiScope Mono';
    }
    if (value.contains('Alibaba PuHuiTi')) return 'Alibaba PuHuiTi';
    if (value.contains('Courier New')) return 'Courier New';
    if (value.contains('Consolas')) return 'Consolas';
    if (value.contains('Fira Code')) return 'Fira Code';
    if (value.contains('Source Code Pro')) return 'Source Code Pro';
    if (value.contains('Menlo') || value.contains('Monaco')) return 'Menlo';
    return value;
  }

  Future<void> updateTerminalTheme(String theme) async {
    terminalTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terminal_theme', theme);
    notifyListeners();
  }

  Future<void> toggleQuickToggle(bool value) async {
    useQuickToggle = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_quick_toggle', value);
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    String modeStr = 'dark';
    if (mode == ThemeMode.light) {
      modeStr = 'light';
    } else if (mode == ThemeMode.system) {
      modeStr = 'system';
    }
    await prefs.setString('theme_mode', modeStr);
    notifyListeners();
  }

  Future<void> updateLocale(String newLocale) async {
    locale = newLocale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', newLocale);
    notifyListeners();
  }

  // ── User Management ──

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await apiService.get('/api/users');
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get users error: $e');
      return [];
    }
  }

  Future<bool> createUser(Map<String, dynamic> userData) async {
    try {
      await apiService.post('/api/users', userData);
      return true;
    } catch (e) {
      print('Create user error: $e');
      return false;
    }
  }

  Future<bool> updateUser(int id, Map<String, dynamic> userData) async {
    try {
      await apiService.put('/api/users/$id', userData);
      return true;
    } catch (e) {
      print('Update user error: $e');
      return false;
    }
  }

  Future<bool> deleteUser(int id) async {
    try {
      await apiService.delete('/api/users/$id');
      return true;
    } catch (e) {
      print('Delete user error: $e');
      return false;
    }
  }

  Future<bool> resetUserPassword(int id) async {
    try {
      await apiService.put('/api/users/$id', {'password': 'TermiScope123456!'});
      return true;
    } catch (e) {
      print('Reset user password error: $e');
      return false;
    }
  }

  Future<bool> toggleUserStatus(int id, bool isActive) async {
    try {
      final statusStr = isActive ? 'active' : 'disabled';
      await apiService.put('/api/users/$id', {'status': statusStr});
      return true;
    } catch (e) {
      print('Toggle user status error: $e');
      return false;
    }
  }

  // ── SFTP File Transfer ──

  Future<List<Map<String, dynamic>>> listFiles(
      String hostId, String path) async {
    try {
      final endpoint =
          '/api/sftp/list/$hostId?path=${Uri.encodeComponent(path)}';
      final response = await apiService.get(endpoint);
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('SFTP listFiles error: $e');
      return [];
    }
  }

  Future<bool> createDirectory(String hostId, String path) async {
    try {
      await apiService.post('/api/sftp/mkdir/$hostId', {'path': path});
      return true;
    } catch (e) {
      print('SFTP mkdir error: $e');
      return false;
    }
  }

  Future<bool> createFile(String hostId, String path) async {
    try {
      await apiService.post('/api/sftp/create/$hostId', {'path': path});
      return true;
    } catch (e) {
      print('SFTP create file error: $e');
      return false;
    }
  }

  Future<bool> renameFile(String hostId, String oldPath, String newPath) async {
    try {
      await apiService.post('/api/sftp/rename/$hostId',
          {'old_path': oldPath, 'new_path': newPath});
      return true;
    } catch (e) {
      print('SFTP rename error: $e');
      return false;
    }
  }

  Future<bool> deleteFile(String hostId, String path) async {
    try {
      final endpoint =
          '/api/sftp/delete/$hostId?path=${Uri.encodeComponent(path)}';
      await apiService.delete(endpoint);
      return true;
    } catch (e) {
      print('SFTP delete error: $e');
      return false;
    }
  }

  // ── Recording Management ──

  Future<List<Map<String, dynamic>>> getRecordings() async {
    try {
      final response = await apiService.get('/api/recordings');
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get recordings error: $e');
      return [];
    }
  }

  Future<bool> deleteRecording(dynamic id) async {
    try {
      await apiService.delete('/api/recordings/$id');
      return true;
    } catch (e) {
      print('Delete recording error: $e');
      return false;
    }
  }

  // ── System Management & Database & Latency Grid ──

  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final response = await apiService.get('/api/system/settings');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      print('Get system settings error: $e');
      return {};
    }
  }

  Future<bool> saveSystemSettings(Map<String, dynamic> settings) async {
    try {
      await apiService.put('/api/system/settings', settings);
      return true;
    } catch (e) {
      print('Save system settings error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getDbStats() async {
    try {
      final response = await apiService.get('/api/system/db-stats');
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      print('Get DB stats error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> pruneMonitorData() async {
    try {
      final response =
          await apiService.post('/api/system/db-maintenance/prune', {});
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      print('Prune monitor data error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> backupDatabase(String password) async {
    try {
      final response =
          await apiService.post('/api/system/backup', {'password': password});
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {};
    } catch (e) {
      print('Backup database error: $e');
      return {};
    }
  }

  Future<bool> testEmailNotification(Map<String, dynamic> data) async {
    try {
      await apiService.post('/api/system/settings/test-email', data);
      return true;
    } catch (e) {
      print('Test email error: $e');
      return false;
    }
  }

  Future<bool> testTelegramNotification(Map<String, dynamic> data) async {
    try {
      await apiService.post('/api/system/settings/test-telegram', data);
      return true;
    } catch (e) {
      print('Test Telegram error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getNetworkTemplates() async {
    try {
      final response = await apiService.get('/api/monitor/network/templates');
      if (response is List) {
        return response.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get network templates error: $e');
      return [];
    }
  }

  Future<bool> createNetworkTemplate(Map<String, dynamic> data) async {
    try {
      await apiService.post('/api/monitor/network/templates', data);
      return true;
    } catch (e) {
      print('Create network template error: $e');
      return false;
    }
  }

  Future<bool> updateNetworkTemplate(int id, Map<String, dynamic> data) async {
    try {
      await apiService.put('/api/monitor/network/templates/$id', data);
      return true;
    } catch (e) {
      print('Update network template error: $e');
      return false;
    }
  }

  Future<bool> deleteNetworkTemplate(int id) async {
    try {
      await apiService.delete('/api/monitor/network/templates/$id');
      return true;
    } catch (e) {
      print('Delete network template error: $e');
      return false;
    }
  }

  Future<bool> batchApplyNetworkTemplate(
      int templateId, List<int> hostIds) async {
    try {
      await apiService.post('/api/network-monitor/batch-apply-template', {
        'template_id': templateId,
        'host_ids': hostIds,
      });
      return true;
    } catch (e) {
      print('Batch apply network template error: $e');
      return false;
    }
  }
}
