import 'package:flutter/material.dart';

class TerminalProvider extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  String? _activeSessionId;

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  String? get activeSessionId => _activeSessionId;

  TerminalSession? getSession(String sessionId) {
    try {
      return _sessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  String addSession({
    required int hostId,
    required String name,
    bool record = false,
  }) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _sessions.add(
      TerminalSession(id: id, hostId: hostId, name: name, record: record),
    );
    _activeSessionId = id;
    notifyListeners();
    return id;
  }

  void removeSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    notifyListeners();
  }

  void setActiveSession(String sessionId) {
    if (_sessions.any((s) => s.id == sessionId)) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  TerminalSession? findSessionByHostId(int hostId) {
    try {
      return _sessions.firstWhere((s) => s.hostId == hostId);
    } catch (e) {
      return null;
    }
  }
}

class TerminalSession {
  final String id;
  final int hostId;
  final String name;
  final bool record;

  TerminalSession({
    required this.id,
    required this.hostId,
    required this.name,
    this.record = false,
  });
}
