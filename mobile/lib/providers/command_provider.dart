import 'package:flutter/material.dart';
import '../models/command.dart';
import '../services/command_service.dart';

class CommandProvider extends ChangeNotifier {
  final CommandService _commandService;
  List<CommandTemplate> _commandTemplates = [];
  bool _isLoading = false;
  String? _error;

  CommandProvider(this._commandService);

  List<CommandTemplate> get commandTemplates => _commandTemplates;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fetch all command templates
  Future<void> fetchCommandTemplates() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _commandTemplates = await _commandService.getCommandTemplates();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new command template
  Future<bool> createCommandTemplate(CommandTemplate commandTemplate) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newTemplate = await _commandService.createCommandTemplate(commandTemplate);
      _commandTemplates.add(newTemplate);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Update an existing command template
  Future<bool> updateCommandTemplate(int id, CommandTemplate commandTemplate) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedTemplate = await _commandService.updateCommandTemplate(id, commandTemplate);
      final index = _commandTemplates.indexWhere((template) => template.id == id);
      if (index != -1) {
        _commandTemplates[index] = updatedTemplate;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Delete a command template
  Future<bool> deleteCommandTemplate(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _commandService.deleteCommandTemplate(id);
      if (success) {
        _commandTemplates.removeWhere((template) => template.id == id);
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Execute a command on a host
  Future<Map<String, dynamic>> executeCommandOnHost(String hostId, String command) async {
    try {
      return await _commandService.executeCommandOnHost(hostId, command);
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  // Get a command template by ID
  CommandTemplate? getCommandTemplateById(int id) {
    return _commandTemplates.firstWhere((template) => template.id == id, orElse: () => _commandTemplates.first);
  }

  // Refresh the command templates list
  Future<void> refreshCommandTemplates() async {
    await fetchCommandTemplates();
  }
}