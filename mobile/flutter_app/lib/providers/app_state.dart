import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppState extends ChangeNotifier {
  final ApiService apiService = ApiService();
  bool isInitialized = false;
  List<dynamic> hosts = [];
  Map<String, dynamic> monitorData = {}; // host_id -> monitor info

  // Terminal Tab Management
  List<Map<String, dynamic>> activeTerminals = [];
  String? activeTabId;

  // Settings
  double terminalFontSize = 14.0;
  bool useQuickToggle = false;

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

  Future<bool> login(String url, String username, String password, bool rememberMe) async {
    // Save URL temporally to apiService
    apiService.baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    try {
      final data = await apiService.post('/api/auth/login', {
        'username': username,
        'password': password,
        'remember': true,
      });

      final token = data['token'];
      if (token != null) {
        await apiService.saveSettings(
          apiService.baseUrl!,
          token,
          username: rememberMe ? username : null,
          password: rememberMe ? password : null,
        );
        await fetchHosts();
        return true;
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await apiService.logout();
    hosts = [];
    monitorData = {};
    notifyListeners();
  }

  Future<void> fetchHosts() async {
    try {
      final data = await apiService.get('/api/ssh-hosts');
      if (data is List) {
        hosts = data;
        notifyListeners();
      }
    } catch (e) {
      print('Fetch hosts error: $e');
      if (e is UnauthorizedException) {
        await logout();
      }
    }
  }

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
  
  void updateMonitorData(Map<String, dynamic> update) {
    final hostId = update['host_id'].toString();
    if (monitorData.containsKey(hostId)) {
      monitorData[hostId] = {...monitorData[hostId], ...update};
    } else {
      monitorData[hostId] = update;
    }
    notifyListeners();
  }

  // Terminal Tab Helpers
  void addTerminal(Map<String, dynamic> host) {
    final hostIdVal = host['id'];
    // For quick-connect (host id 0) we always create a new session
    if (hostIdVal == 0) {
      final String id = '${hostIdVal}_${DateTime.now().millisecondsSinceEpoch}';
      activeTerminals.add({
        'tabId': id,
        'hostId': hostIdVal,
        'name': host['name'] ?? 'Unnamed',
      });
      activeTabId = id;
      notifyListeners();
      return;
    }

    // If a terminal for this host already exists, activate it instead of creating a duplicate
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
      'name': host['name'] ?? 'Unnamed',
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

  // Host Management
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
      final result = await apiService.post('/api/ssh-hosts/$id', updates);
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
      final result = await apiService.post('/api/ssh-hosts/$id/delete', {});
      if (result != null) {
        await fetchHosts();
        return true;
      }
      return false;
    } catch (e) {
      print('Delete host error: $e');
      return false;
    }
  }

  // Settings management
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
