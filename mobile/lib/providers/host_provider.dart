import 'package:flutter/material.dart';
import '../data/models/host.dart';
import '../data/services/host_service.dart';

class HostProvider extends ChangeNotifier {
  final HostService _hostService;

  List<Host> _hosts = [];
  List<Host> get hosts => _hosts;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  HostProvider(this._hostService);

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
}
