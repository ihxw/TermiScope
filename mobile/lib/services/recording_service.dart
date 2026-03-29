import '../core/api_client.dart';
import '../models/recording.dart';

class RecordingService {
  final ApiClient _apiClient = ApiClient.instance;

  // Get all recordings
  Future<List<Recording>> getRecordings() async {
    try {
      final response = await _apiClient.get('/recordings');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['recordings'] != null) {
          return (data['recordings'] as List)
              .map((json) => Recording.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Delete a recording
  Future<bool> deleteRecording(int id) async {
    try {
      final response = await _apiClient.delete('/recordings/$id');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Download a recording
  Future<String> getRecordingStreamUrl(int id) async {
    try {
      // Get a WebSocket ticket first
      final ticketResponse = await _apiClient.get('/auth/ws-ticket');
      final ticket = ticketResponse.data['ticket'];
      
      // Return the stream URL with the ticket
      return '/api/recordings/$id/stream?token=$ticket';
    } catch (e) {
      rethrow;
    }
  }

  // Get recording details
  Future<Recording> getRecordingDetails(int id) async {
    try {
      final response = await _apiClient.get('/recordings/$id');
      
      if (response.statusCode == 200 && response.data != null) {
        return Recording.fromJson(response.data);
      } else {
        throw Exception('Failed to get recording details');
      }
    } catch (e) {
      rethrow;
    }
  }
}