import '../core/api_client.dart';
import '../models/command.dart';

class CommandService {
  final ApiClient _apiClient = ApiClient.instance;

  // Get all command templates
  Future<List<CommandTemplate>> getCommandTemplates() async {
    try {
      final response = await _apiClient.get('/command-templates');
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        if (data['templates'] != null) {
          return (data['templates'] as List)
              .map((json) => CommandTemplate.fromJson(json))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  // Create a new command template
  Future<CommandTemplate> createCommandTemplate(CommandTemplate commandTemplate) async {
    try {
      final response = await _apiClient.post('/command-templates', data: commandTemplate.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return CommandTemplate.fromJson(response.data);
      } else {
        throw Exception('Failed to create command template');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Update an existing command template
  Future<CommandTemplate> updateCommandTemplate(int id, CommandTemplate commandTemplate) async {
    try {
      final response = await _apiClient.put('/command-templates/$id', data: commandTemplate.toJson());
      
      if (response.statusCode == 200 && response.data != null) {
        return CommandTemplate.fromJson(response.data);
      } else {
        throw Exception('Failed to update command template');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Delete a command template
  Future<bool> deleteCommandTemplate(int id) async {
    try {
      final response = await _apiClient.delete('/command-templates/$id');
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Execute a command on a host
  Future<Map<String, dynamic>> executeCommandOnHost(String hostId, String command) async {
    try {
      final response = await _apiClient.post('/command/execute', data: {
        'host_id': hostId,
        'command': command,
      });
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Failed to execute command');
      }
    } catch (e) {
      rethrow;
    }
  }
}