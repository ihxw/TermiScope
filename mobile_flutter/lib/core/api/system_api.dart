import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

final systemApiProvider =
    Provider((ref) => SystemApi(ref.read(apiClientProvider)));

class SystemApi {
  final ApiClient _client;

  SystemApi(this._client);

  // System Settings
  Future<Map<String, dynamic>> getSettings() async {
    final response = await _client.get('/system/settings');
    return response as Map<String, dynamic>;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _client.post('/system/settings', data: settings);
  }

  // Database
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final response = await _client.get('/system/db/stats');
    return response as Map<String, dynamic>;
  }

  Future<void> backupDatabase() async {
    // This usually triggers a download, might be complex on mobile.
    // For now just call API.
    await _client.post('/system/db/backup');
  }
}
