import 'package:flutter/material.dart';
import '../models/recording.dart';
import '../services/recording_service.dart';

class RecordingProvider extends ChangeNotifier {
  final RecordingService _recordingService;
  List<Recording> _recordings = [];
  bool _isLoading = false;
  String? _error;

  RecordingProvider(this._recordingService);

  List<Recording> get recordings => _recordings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Fetch all recordings
  Future<void> fetchRecordings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _recordings = await _recordingService.getRecordings();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a recording
  Future<bool> deleteRecording(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _recordingService.deleteRecording(id);
      if (success) {
        _recordings.removeWhere((recording) => recording.id == id);
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

  // Get recording stream URL
  Future<String> getRecordingStreamUrl(int id) async {
    try {
      return await _recordingService.getRecordingStreamUrl(id);
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  // Get recording details
  Future<Recording> getRecordingDetails(int id) async {
    try {
      return await _recordingService.getRecordingDetails(id);
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  // Refresh the recordings list
  Future<void> refreshRecordings() async {
    await fetchRecordings();
  }
}