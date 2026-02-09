import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../data/models/sftp_file.dart';
import '../../data/services/api_service.dart';
import '../../data/services/sftp_service.dart';

class SftpBrowserWidget extends StatefulWidget {
  final int hostId;

  const SftpBrowserWidget({super.key, required this.hostId});

  @override
  State<SftpBrowserWidget> createState() => _SftpBrowserWidgetState();
}

class _SftpBrowserWidgetState extends State<SftpBrowserWidget> {
  late final SftpService _sftpService;
  List<SftpFile> _files = [];
  String _currentPath = '.';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final apiService = Provider.of<ApiService>(context, listen: false);
    _sftpService = SftpService(apiService);
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final result = await _sftpService.listFiles(widget.hostId, _currentPath);
      if (mounted) {
        setState(() {
          // result['files']已经是List<SftpFile>类型
          final filesList = result['files'];
          if (filesList is List<SftpFile>) {
            _files = filesList;
          } else {
            _files = [];
          }
          _currentPath = result['cwd'] as String? ?? '.';
        });

        // 异步加载目录大小
        for (int i = 0; i < _files.length; i++) {
          if (_files[i].isDir) {
            final file = _files[i];
            final fullPath = _currentPath == '.'
                ? file.name
                : '$_currentPath/${file.name}';
            _sftpService
                .getDirSize(widget.hostId, fullPath)
                .then((size) {
                  if (mounted && size != null) {
                    setState(() {
                      // 更新该文件的大小
                      final index = _files.indexWhere(
                        (f) => f.name == file.name,
                      );
                      if (index != -1) {
                        _files[index] = SftpFile(
                          name: file.name,
                          isDir: file.isDir,
                          size: size,
                          modTime: file.modTime,
                        );
                      }
                    });
                  }
                })
                .catchError((e) {
                  // 静默处理getDirSize错误
                  debugPrint('Failed to get size for ${file.name}: $e');
                });
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load files: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载文件失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _enterDirectory(String name) {
    setState(() {
      if (_currentPath == '.') {
        _currentPath = name;
      } else {
        _currentPath = _currentPath.endsWith('/')
            ? '$_currentPath$name'
            : '$_currentPath/$name';
      }
    });
    _loadFiles();
  }

  void _navigateToPath(int index) {
    final parts = _pathParts;
    if (index == 0) {
      setState(() {
        _currentPath = _currentPath.startsWith('/') ? '/' : '.';
      });
    } else {
      final newPath = parts.sublist(0, index + 1).join('/');
      setState(() {
        _currentPath = newPath.isEmpty ? '/' : newPath;
      });
    }
    _loadFiles();
  }

  List<String> get _pathParts {
    if (_currentPath == '.') return [''];
    if (_currentPath == '/') return [''];
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    return ['', ...parts];
  }

  String _formatSize(int bytes) {
    if (bytes == 0) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (bytes == 0) ? 0 : (bytes.bitLength - 1) ~/ 10;
    final size = bytes / (1 << (i * 10));
    return '${size.toStringAsFixed(2)} ${sizes[i]}';
  }

  Future<void> _deleteFile(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$name" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final fullPath = _currentPath == '.' ? name : '$_currentPath/$name';
        await _sftpService.deleteFile(widget.hostId, fullPath);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除成功')));
          _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Future<void> _createDirectory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '文件夹名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        final fullPath = _currentPath == '.' ? name : '$_currentPath/$name';
        await _sftpService.createDirectory(widget.hostId, fullPath);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('创建成功')));
          _loadFiles();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Column(
        children: [
          // 顶部工具栏
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                ),
              ),
            ),
            child: Column(
              children: [
                // 按钮行
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loadFiles,
                      tooltip: '刷新',
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder, size: 20),
                      onPressed: _createDirectory,
                      tooltip: '新建文件夹',
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 4),
                // 面包屑导航
                SizedBox(
                  height: 24,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pathParts.length,
                    itemBuilder: (context, index) {
                      final part = _pathParts[index];
                      return Row(
                        children: [
                          InkWell(
                            onTap: () => _navigateToPath(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                part.isEmpty ? '/' : part,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.blue.shade300
                                      : Colors.blue,
                                ),
                              ),
                            ),
                          ),
                          if (index < _pathParts.length - 1)
                            Text(
                              '>',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey
                                    : Colors.grey.shade600,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 文件列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                ? const Center(child: Text('空文件夹'))
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          file.isDir ? Icons.folder : Icons.insert_drive_file,
                          color: file.isDir
                              ? Colors.amber
                              : Colors.grey.shade600,
                          size: 20,
                        ),
                        title: Text(
                          file.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: file.isDir
                            ? null
                            : Text(
                                _formatSize(file.size),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                        trailing: PopupMenuButton<String>(
                          iconSize: 20,
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deleteFile(file.name);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text('删除', style: TextStyle(fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: file.isDir
                            ? () => _enterDirectory(file.name)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
