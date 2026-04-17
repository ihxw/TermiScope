import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  String? baseUrl;
  String? token;

  ApiService();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('server_url') ?? '';
    token = prefs.getString('token') ?? '';
  }

  Future<void> saveSettings(String url, String newToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    await prefs.setString('token', newToken);
    baseUrl = url;
    token = newToken;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    token = '';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer $token',
      };

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Server URL not set');
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return await _processResponse(response);
  }

  Future<dynamic> get(String endpoint) async {
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception('Server URL not set');
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
    );
    return await _processResponse(response);
  }

  // Custom exception to indicate unauthorized responses
  // Thrown when server returns 401 so callers can react (e.g., force logout)
  // Note: keep this simple to avoid adding extra dependencies
  // Usage: catch (e) if (e is UnauthorizedException)
  dynamic _unauthorizedError(http.Response response) => UnauthorizedException('${response.statusCode} - ${response.body}');

  Future<dynamic> _processResponse(http.Response response) async {
    if (response.statusCode == 401) {
      // Clear saved token to force re-login
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
      } catch (e) {
        // ignore prefs errors
      }
      token = '';
      throw _unauthorizedError(response);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final jsonResponse = jsonDecode(response.body);
      if (jsonResponse['success'] == true) {
        return jsonResponse['data'];
      }
      return jsonResponse;
    } else {
      throw Exception('Failed to load data: ${response.statusCode} - ${response.body}');
    }
  }

}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}
