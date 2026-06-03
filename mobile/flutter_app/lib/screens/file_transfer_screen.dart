import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../utils/translation.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  Host? _selectedHost;
  String _currentPath = '/';
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = false;

  void _selectHost(Host host) {
    setState(() {
      _selectedHost = host;
      _currentPath = '/';
      _files = [];
    });
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    if (_selectedHost == null) return;
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final data = await state.listFiles(_selectedHost!.id.toString(), _currentPath);
    setState(() {
      _files = data;
      _isLoading = false;
    });
  }

  void _navigateInto(Map<String, dynamic> file) {
    if (file['is_dir'] == true) {
      final name = file['name'];
      setState(() {
        if (_currentPath.endsWith('/')) {
          _currentPath = '$_currentPath$name';
        } else {
          _currentPath = '$_currentPath/$name';
        }
      });
      _loadFiles();
    }
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/');
    parts.removeLast();
    setState(() {
      _currentPath = parts.join('/');
      if (_currentPath.isEmpty) _currentPath = '/';
    });
    _loadFiles();
  }

  void _showCreateDirectoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'sftp.newFolder')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: Translation.getText(state.locale, 'sftp.folderName'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final newPath = _currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name';
                final success = await state.createDirectory(_selectedHost!.id.toString(), newPath);
                if (success) {
                  _loadFiles();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(Map<String, dynamic> file) {
    final controller = TextEditingController(text: file['name']);
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'sftp.newName')),
          content: TextField(
            controller: controller,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final oldFullPath = _currentPath.endsWith('/') ? '$_currentPath${file['name']}' : '$_currentPath/${file['name']}';
                final newFullPath = _currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name';
                final success = await state.renameFile(_selectedHost!.id.toString(), oldFullPath, newFullPath);
                if (success) {
                  _loadFiles();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5C35)),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (ctx) {
        final state = Provider.of<AppState>(context, listen: false);
        return AlertDialog(
          title: Text(Translation.getText(state.locale, 'common.confirmDelete')),
          content: Text('${file['name']}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(Translation.getText(state.locale, 'common.cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final fullPath = _currentPath.endsWith('/') ? '$_currentPath${file['name']}' : '$_currentPath/${file['name']}';
                final success = await state.deleteFile(_selectedHost!.id.toString(), fullPath);
                if (success) {
                  _loadFiles();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text(Translation.getText(state.locale, 'common.confirm')),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Widget _buildHostSelection(AppState state) {
    final sshHosts = state.hosts.where((h) => h.hostType != 'monitor_only').toList();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.swap_horiz, size: 72, color: Color(0xFFFF5C35)),
            const SizedBox(height: 24),
            Text(
              Translation.getText(state.locale, 'sftp.selectHost'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (sshHosts.isEmpty)
              Text(
                Translation.getText(state.locale, 'sftp.emptyFolder'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              )
            else
              Container(
                height: 240,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: ListView.builder(
                  itemCount: sshHosts.length,
                  itemBuilder: (ctx, idx) {
                    final h = sshHosts[idx];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFF5C35),
                        child: Icon(Icons.terminal, color: Colors.white, size: 18),
                      ),
                      title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${h.host}:${h.port}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () => _selectHost(h),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    if (_selectedHost == null) {
      return _buildHostSelection(state);
    }

    return Scaffold(
      body: Column(
        children: [
          // Breadcrumb Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: 'Go Up',
                  onPressed: _currentPath == '/' ? null : _navigateUp,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _currentPath,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFFFF5C35), size: 20),
                  onPressed: _showCreateDirectoryDialog,
                  tooltip: Translation.getText(state.locale, 'sftp.newFolder'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadFiles,
                  tooltip: Translation.getText(state.locale, 'common.refresh'),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                  onPressed: () => setState(() => _selectedHost = null),
                  tooltip: 'Disconnect',
                ),
              ],
            ),
          ),
          // File List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? Center(
                        child: Text(
                          Translation.getText(state.locale, 'sftp.emptyFolder'),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (ctx, idx) {
                          final file = _files[idx];
                          final isDir = file['is_dir'] == true;
                          final size = file['size'] != null ? _formatBytes(file['size'] as int) : '-';

                          return ListTile(
                            leading: Icon(
                              isDir ? Icons.folder : Icons.insert_drive_file,
                              color: isDir ? Colors.amber : Colors.grey,
                            ),
                            title: Text(
                              file['name'] ?? '',
                              style: TextStyle(fontWeight: isDir ? FontWeight.bold : FontWeight.normal),
                            ),
                            subtitle: Text(
                              '$size 鈥?${file['modified_time'] ?? ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'rename') {
                                  _showRenameDialog(file);
                                } else if (val == 'delete') {
                                  _confirmDelete(file);
                                } else if (val == 'download') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Simulated Download: ${file['name']}')),
                                  );
                                }
                              },
                              itemBuilder: (c) => [
                                if (!isDir)
                                  PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.download, size: 18),
                                        const SizedBox(width: 8),
                                        Text(Translation.getText(state.locale, 'sftp.download')),
                                      ],
                                    ),
                                  ),
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit, size: 18),
                                      const SizedBox(width: 8),
                                      Text(Translation.getText(state.locale, 'common.edit')),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                      const SizedBox(width: 8),
                                      Text(Translation.getText(state.locale, 'common.delete'), style: const TextStyle(color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              if (isDir) {
                                _navigateInto(file);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
