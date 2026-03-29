import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/sftp_file.dart';

class SftpService {
  final ApiClient _apiClient = ApiClient.instance;

  // List directory contents
  Future<SftpDirectoryContent> listDirectory(String hostId, String path) async {
    try {
      final response = await _apiClient.get(
        '/sftp/list/$hostId',
        params: {'path': path},
      );
      
      if (response.statusCode == 200 && response.data != null) {
        return SftpDirectoryContent.fromJson(response.data);
      } else {
        throw Exception('Failed to list directory');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Download file
  Future<Uint8List> downloadFile(String hostId, String filePath) async {
    try {
      final response = await _apiClient.get(
        '/sftp/download/$hostId',
        params: {'path': filePath},
      );
      
      if (response.statusCode == 200 && response.data != null) {
        return Uint8List.fromList(response.data);
      } else {
        throw Exception('Failed to download file');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Upload file
  Future<bool> uploadFile(String hostId, String filePath, Uint8List fileData) async {
    try {
      final formData = FormData.fromMap({
        'path': filePath,
        'file': MultipartFile.fromBytes(fileData, filename: filePath.split('/').last),
      });

      final response = await _apiClient.post(
        '/sftp/upload/$hostId',
        data: formData,
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Delete file or directory
  Future<bool> deletePath(String hostId, String path) async {
    try {
      final response = await _apiClient.delete(
        '/sftp/delete/$hostId',
        params: {'path': path},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Rename file or directory
  Future<bool> renamePath(String hostId, String oldPath, String newPath) async {
    try {
      final response = await _apiClient.post(
        '/sftp/rename/$hostId',
        data: {
          'old_path': oldPath,
          'new_path': newPath,
        },
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Copy or move file/directory
  Future<bool> copyOrMove(String hostId, String source, String dest, String type) async {
    try {
      final response = await _apiClient.post(
        '/sftp/paste/$hostId',
        data: {
          'source': source,
          'dest': dest,
          'type': type, // 'copy' or 'move'
        },
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Create directory
  Future<bool> createDirectory(String hostId, String path) async {
    try {
      final response = await _apiClient.post(
        '/sftp/mkdir/$hostId',
        data: {'path': path},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Create file
  Future<bool> createFile(String hostId, String path) async {
    try {
      final response = await _apiClient.post(
        '/sftp/create/$hostId',
        data: {'path': path},
      );
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get file size
  Future<int> getFileSize(String hostId, String path) async {
    try {
      final response = await _apiClient.get(
        '/sftp/size/$hostId',
        params: {'path': path},
      );
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data['size'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
}