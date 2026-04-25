import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppState extends ChangeNotifier {
  final ApiService apiService = ApiService();
  bool isInitialized = false;
  List<Host> hosts = [];
  Map<String, dynamic> monitorData = {}; // host_id -> monitor info

  // Terminal Tab Management
  List<Map<String, dynamic>> activeTerminals = [];
  String? activeTabId;

  // Settings
  double terminalFontSize = 14.0;
  bool useQuickToggle = false;

  // Profile
  UserProfile? profile;

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
    useQuickToggle = prefs.getBool('use_quick_toggle') ?? false;
    // Load saved terminals
    await _loadSavedTerminals();
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

  Future<Map<String, dynamic>> login(String url, String username, String password, bool rememberMe) async {
    apiService.baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

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
          username: rememberMe ? username : null,
          password: rememberMe ? password : null,
        );
        await fetchHosts();
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      print('Login error: $e');
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

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    try {
      await apiService.post('/api/auth/change-password', {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
      return true;
    } catch (e) {
      print('Change password error: $e');
      return false;
    }
  }

  Future<void> fetchLoginHistory() async {
    try {
      final data = await apiService.get('/api/auth/login-history?page=1&page_size=20');
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
        hosts = data.map((e) => Host.fromJson(Map<String, dynamic>.from(e))).toList();
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

  /// Test SSH connection to a host
  Future<Map<String, dynamic>> testHostConnection(String id) async {
    try {
      final result = await apiService.post('/api/ssh-hosts/$id/test', {});
      return {'success': true, 'message': result is Map ? result['message'] : 'Connection successful'};
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

  Future<bool> createCommandTemplate(String name, String command, String description) async {
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

  Future<bool> updateCommandTemplate(int id, String name, String command, String description) async {
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
      var endpoint = '/api/connection-logs?page=$connectionLogsPage&page_size=$_logsPageSize';
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

  void addTerminal(Host host) {
    final hostIdVal = host.id;
    if (hostIdVal == 0) {
      final String id = '${hostIdVal}_${DateTime.now().millisecondsSinceEpoch}';
      activeTerminals.add({
        'tabId': id,
        'hostId': hostIdVal,
        'name': host.name,
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
    });
    activeTabId = id;
    notifyListeners();
  }

  void removeTerminal(String tabId) {
    activeTerminals.removeWhere((t) => t['tabId'] == tabId);
    if (activeTabId == tabId) {
      activeTabId = activeTerminals.isNotEmpty ? activeTerminals.last['tabId'] : null;
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

  Future<void> toggleQuickToggle(bool value) async {
    useQuickToggle = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_quick_toggle', value);
    notifyListeners();
  }
}
