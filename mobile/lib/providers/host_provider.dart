import 'package:flutter/material.dart';
import '../models/ssh_host.dart';
import '../services/host_service.dart';

class HostProvider extends ChangeNotifier {
  final HostService _hostService;

  List<SSHHost> _hosts = [];
  List<SSHHost> get hosts => _hosts;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  HostProvider(this._hostService);

  Future<void> reorderHosts(List<int> ids) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orderedIds = await _hostService.reorderHosts(ids);
      // Refresh the host list to reflect the new order
      await fetchHosts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> testConnection(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _hostService.testConnection(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deployMonitor(int id, {bool insecure = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _hostService.deployMonitor(id, insecure: insecure);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> stopMonitor(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _hostService.stopMonitor(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateAgent(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _hostService.updateAgent(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchHosts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _hosts = await _hostService.getHosts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addHost(SSHHost host) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final newHost = await _hostService.createHost(host);
      _hosts.add(newHost);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateHost(SSHHost host) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedHost = await _hostService.updateHost(host.id, host);
      final index = _hosts.indexWhere((h) => h.id == host.id);
      if (index != -1) {
        _hosts[index] = updatedHost;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteHost(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _hostService.deleteHost(id);
      _hosts.removeWhere((h) => h.id == id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
