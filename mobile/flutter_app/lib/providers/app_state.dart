import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class AppState extends ChangeNotifier {
  final ApiService apiService = ApiService();
  bool isInitialized = false;
  List<dynamic> hosts = [];
  Map<String, dynamic> monitorData = {}; // host_id -> monitor info

  Future<void> init() async {
    await apiService.init();
    isInitialized = true;
    notifyListeners();
  }

  Future<bool> login(String url, String username, String password) async {
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
        await apiService.saveSettings(apiService.baseUrl!, token);
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
    }
  }

  Future<String?> getTicket() async {
    try {
      final data = await apiService.post('/api/auth/ws-ticket', {});
      return data['ticket'];
    } catch (e) {
      print('Get ticket error: $e');
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
}
