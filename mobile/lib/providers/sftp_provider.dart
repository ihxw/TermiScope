import 'package:flutter/material.dart';
import '../models/sftp_file.dart';
import '../services/sftp_service.dart';
import 'dart:typed_data';

class SftpProvider extends ChangeNotifier {
  final SftpService _sftpService;
  SftpDirectoryContent? _currentDirectory;
  String? _currentHostId;
  bool _isLoading = false;
  String? _error;

  SftpProvider(this._sftpService);

  SftpDirectoryContent? get currentDirectory => _currentDirectory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentHostId => _currentHostId;

  // Browse to a directory
  Future<void> browseDirectory(String hostId, String path) async {
    _isLoading = true;
    _error = null;
    _currentHostId = hostId;
    notifyListeners();

    try {
      _currentDirectory = await _sftpService.listDirectory(hostId, path);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Navigate up one level
  Future<void> navigateUp() async {
    if (_currentDirectory == null || _currentDirectory!.currentPath == '/') {
      return;
    }

    String parentPath = _currentDirectory!.currentPath;
    if (parentPath.endsWith('/')) {
      parentPath = parentPath.substring(0, parentPath.length - 1);
    }
    parentPath = parentPath.substring(0, parentPath.lastIndexOf('/'));
    if (parentPath.isEmpty) {
      parentPath = '/';
    }

    await browseDirectory(_currentHostId!, parentPath);
  }

  // Navigate to a subdirectory
  Future<void> navigateToSubdirectory(String subdirectoryName) async {
    if (_currentDirectory == null) return;

    String newPath = _currentDirectory!.currentPath;
    if (!newPath.endsWith('/')) {
      newPath += '/';
    }
    newPath += subdirectoryName;

    await browseDirectory(_currentHostId!, newPath);
  }

  // Refresh current directory
  Future<void> refreshDirectory() async {
    if (_currentDirectory == null) return;
    await browseDirectory(_currentHostId!, _currentDirectory!.currentPath);
  }

  // Upload a file
  Future<bool> uploadFile(String filePath, Uint8List fileData) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.uploadFile(_currentHostId!, filePath, fileData);
      if (result) {
        // Refresh directory after successful upload
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Download a file
  Future<Uint8List?> downloadFile(String filePath) async {
    if (_currentHostId == null) return null;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _sftpService.downloadFile(_currentHostId!, filePath);
      return data;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a file or directory
  Future<bool> deletePath(String path) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.deletePath(_currentHostId!, path);
      if (result) {
        // Refresh directory after successful deletion
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Rename a file or directory
  Future<bool> renamePath(String oldPath, String newPath) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.renamePath(_currentHostId!, oldPath, newPath);
      if (result) {
        // Refresh directory after successful rename
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a directory
  Future<bool> createDirectory(String path) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.createDirectory(_currentHostId!, path);
      if (result) {
        // Refresh directory after successful creation
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a file
  Future<bool> createFile(String path) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.createFile(_currentHostId!, path);
      if (result) {
        // Refresh directory after successful creation
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get file size
  Future<int> getFileSize(String path) async {
    if (_currentHostId == null) return 0;
    return await _sftpService.getFileSize(_currentHostId!, path);
  }

  // Copy or move a file/directory
  Future<bool> copyOrMove(String source, String dest, String type) async {
    if (_currentHostId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _sftpService.copyOrMove(_currentHostId!, source, dest, type);
      if (result) {
        // Refresh directory after successful operation
        await refreshDirectory();
      }
      return result;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}