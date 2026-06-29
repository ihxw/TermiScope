import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../app/antd_tokens.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({super.key});
  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  Host? _selectedHost;
  String _currentPath = '/';
  List<Map<String, dynamic>> _files = [];
  final List<String> _backHistory = [];
  final List<String> _forwardHistory = [];
  bool _isLoading = false;

  final _pathController = TextEditingController(text: '/');
  List<String> _sftpHistory = [];
  List<String> _sftpFavorites = [];

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _selectHost(Host host) {
    setState(() {
      _selectedHost = host;
      _currentPath = '/';
      _pathController.text = '/';
      _files = [];
      _backHistory.clear();
      _forwardHistory.clear();
    });
    _loadHistoryAndFavorites();
    _loadFiles();
  }

  Future<void> _loadHistoryAndFavorites() async {
    if (_selectedHost == null) return;
    final prefs = await SharedPreferences.getInstance();
    final hostId = _selectedHost!.id.toString();
    setState(() {
      _sftpHistory = prefs.getStringList('sftp_history_$hostId') ?? [];
      _sftpFavorites = prefs.getStringList('sftp_favorites_$hostId') ?? [];
    });
  }

  Future<void> _addToHistory(String path) async {
    if (path.trim().isEmpty || _selectedHost == null) return;
    final hostId = _selectedHost!.id.toString();
    final list = List<String>.from(_sftpHistory);
    list.remove(path);
    list.insert(0, path);
    if (list.length > 15) {
      list.removeRange(15, list.length);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sftp_history_$hostId', list);
    if (mounted) {
      setState(() {
        _sftpHistory = list;
      });
    }
  }

  Future<void> _clearHistory() async {
    if (_selectedHost == null) return;
    final hostId = _selectedHost!.id.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sftp_history_$hostId');
    if (mounted) {
      setState(() {
        _sftpHistory = [];
      });
    }
  }

  Future<void> _addCurrentToFavorites() async {
    if (_currentPath.trim().isEmpty || _selectedHost == null) return;
    final hostId = _selectedHost!.id.toString();
    if (_sftpFavorites.contains(_currentPath)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该路径已在收藏夹中')),
        );
      }
      return;
    }
    final list = List<String>.from(_sftpFavorites)..add(_currentPath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sftp_favorites_$hostId', list);
    if (mounted) {
      setState(() {
        _sftpFavorites = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加至收藏夹')),
      );
    }
  }

  Future<void> _removeFavorite(String path) async {
    if (_selectedHost == null) return;
    final hostId = _selectedHost!.id.toString();
    final list = List<String>.from(_sftpFavorites)..remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('sftp_favorites_$hostId', list);
    if (mounted) {
      setState(() {
        _sftpFavorites = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从收藏夹移除')),
      );
    }
  }

  void _showHistoryBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '历史打开记录',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (_sftpHistory.isNotEmpty)
                          TextButton.icon(
                            onPressed: () async {
                              await _clearHistory();
                              setBottomSheetState(() {});
                              if (mounted) setState(() {});
                            },
                            icon: const Icon(Icons.delete_sweep, size: 16, color: AntdTokens.error),
                            label: const Text('清空', style: TextStyle(color: AntdTokens.error)),
                          ),
                      ],
                    ),
                    const Divider(),
                    if (_sftpHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.0),
                        child: AntdEmpty(description: '暂无历史记录'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _sftpHistory.length,
                          itemBuilder: (context, index) {
                            final path = _sftpHistory[index];
                            return ListTile(
                              leading: const Icon(Icons.folder_open, color: Colors.amber),
                              title: Text(path, style: const TextStyle(fontSize: 14)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _goToPath(path);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFavoritesBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            final isFavorite = _sftpFavorites.contains(_currentPath);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '收藏夹',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            if (isFavorite) {
                              await _removeFavorite(_currentPath);
                            } else {
                              await _addCurrentToFavorites();
                            }
                            setBottomSheetState(() {});
                            if (mounted) setState(() {});
                          },
                          icon: Icon(isFavorite ? Icons.star : Icons.star_border, size: 16, color: Colors.orange),
                          label: Text(isFavorite ? '取消收藏当前' : '收藏当前路径', style: const TextStyle(color: Colors.orange)),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_sftpFavorites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32.0),
                        child: AntdEmpty(description: '暂无收藏路径'),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _sftpFavorites.length,
                          itemBuilder: (context, index) {
                            final path = _sftpFavorites[index];
                            return ListTile(
                              leading: const Icon(Icons.star, color: Colors.orange),
                              title: Text(path, style: const TextStyle(fontSize: 14)),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16, color: AntdTokens.error),
                                onPressed: () async {
                                  await _removeFavorite(path);
                                  setBottomSheetState(() {});
                                  if (mounted) setState(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _goToPath(path);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _loadFiles() async {
    if (_selectedHost == null) return;
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final data = await state.listFiles(_selectedHost!.id.toString(), _currentPath);
    if (mounted) setState(() { _files = data; _isLoading = false; });
  }

  void _goToPath(String path, {bool addHistory = true}) {
    final normalized = path.trim().isEmpty ? '/' : path.trim();
    final nextPath = normalized.startsWith('/') ? normalized : '/$normalized';
    if (nextPath == _currentPath) return;
    setState(() {
      if (addHistory) { _backHistory.add(_currentPath); _forwardHistory.clear(); }
      _currentPath = nextPath;
      _pathController.text = _currentPath;
    });
    _addToHistory(_currentPath);
    _loadFiles();
  }

  void _navigateInto(Map<String, dynamic> file) {
    if (file['is_dir'] == true) {
      final name = file['name'];
      _goToPath(_currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name');
    }
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/')..removeLast();
    var next = parts.join('/');
    if (next.isEmpty) next = '/';
    _goToPath(next);
  }

  void _goBack() {
    if (_backHistory.isEmpty) return;
    final nextPath = _backHistory.removeLast();
    setState(() {
      _forwardHistory.add(_currentPath);
      _currentPath = nextPath;
      _pathController.text = _currentPath;
    });
    _addToHistory(_currentPath);
    _loadFiles();
  }

  void _goForward() {
    if (_forwardHistory.isEmpty) return;
    final nextPath = _forwardHistory.removeLast();
    setState(() {
      _backHistory.add(_currentPath);
      _currentPath = nextPath;
      _pathController.text = _currentPath;
    });
    _addToHistory(_currentPath);
    _loadFiles();
  }

  void _showPathDialog() {
    final ctrl = TextEditingController(text: _currentPath);
    showDialog(context: context, builder: (_) => AntdModal(
      title: const Text('\u8df3\u8f6c\u8def\u5f84'), width: 400,
      okText: '\u8df3\u8f6c', cancelText: '\u53d6\u6d88',
      onOk: () => _goToPath(ctrl.text),
      child: AntdInput(controller: ctrl, placeholder: '/var/www', autofocus: true,
        onSubmitted: (_) => _goToPath(ctrl.text)),
    ));
  }

  void _showCreateDialog({required bool isDir}) {
    final ctrl = TextEditingController();
    final state = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(isDir ? '\u65b0\u5efa\u6587\u4ef6\u5939' : '\u65b0\u5efa\u6587\u4ef6'), width: 400,
      okText: Translation.getText(state.locale, 'common.confirm'),
      cancelText: Translation.getText(state.locale, 'common.cancel'),
      onOk: () async {
        final name = ctrl.text.trim();
        if (name.isEmpty) return;
        final newPath = _currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name';
        final ok = isDir
            ? await state.createDirectory(_selectedHost!.id.toString(), newPath)
            : await state.createFile(_selectedHost!.id.toString(), newPath);
        if (ok) _loadFiles();
      },
      child: AntdInput(controller: ctrl, placeholder: isDir ? '\u6587\u4ef6\u5939\u540d\u79f0' : '\u6587\u4ef6\u540d'),
    ));
  }

  void _showRenameDialog(Map<String, dynamic> file) {
    final ctrl = TextEditingController(text: file['name']);
    final state = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(Translation.getText(state.locale, 'sftp.newName')), width: 400,
      okText: Translation.getText(state.locale, 'common.confirm'),
      cancelText: Translation.getText(state.locale, 'common.cancel'),
      onOk: () async {
        final name = ctrl.text.trim();
        if (name.isEmpty) return;
        final oldPath = _currentPath.endsWith('/') ? '$_currentPath${file['name']}' : '$_currentPath/${file['name']}';
        final newPath = _currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name';
        final ok = await state.renameFile(_selectedHost!.id.toString(), oldPath, newPath);
        if (ok) _loadFiles();
      },
      child: AntdInput(controller: ctrl),
    ));
  }

  void _confirmDelete(Map<String, dynamic> file) {
    final state = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(Translation.getText(state.locale, 'common.confirmDelete')), width: 400,
      okText: Translation.getText(state.locale, 'common.confirm'),
      cancelText: Translation.getText(state.locale, 'common.cancel'),
      danger: true,
      onOk: () async {
        final fullPath = _currentPath.endsWith('/') ? '$_currentPath${file['name']}' : '$_currentPath/${file['name']}';
        final ok = await state.deleteFile(_selectedHost!.id.toString(), fullPath);
        if (ok) _loadFiles();
      },
      child: Text('\u786e\u5b9a\u8981\u5220\u9664 ${file['name']} \u5417\uff1f'),
    ));
  }

  Widget _buildHostSelection(AppState state) {
    final sshHosts = state.hosts.where((h) => h.hostType != 'monitor_only').toList();
    return LayoutBuilder(builder: (ctx, constraints) {
      final listH = (constraints.maxHeight * 0.45).clamp(120.0, 240.0);
      return Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.swap_horiz, size: 72, color: AntdTokens.primary),
            const SizedBox(height: 24),
            Text(Translation.getText(state.locale, 'sftp.selectHost'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            if (sshHosts.isEmpty)
              AntdEmpty(description: Translation.getText(state.locale, 'sftp.emptyFolder'))
            else
              Container(height: listH, decoration: BoxDecoration(
                color: AntdTokens.containerColor(context),
                borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
                border: Border.all(color: AntdTokens.borderSecondaryColor(context)),
              ), child: ListView.builder(itemCount: sshHosts.length, itemBuilder: (_, i) {
                final h = sshHosts[i];
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: AntdTokens.primary,
                      child: const Icon(Icons.terminal, color: Colors.white, size: 18)),
                    title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${h.host}:${h.port}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () => _selectHost(h),
                  ),
                );
              })),
          ]),
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    if (_selectedHost == null) return _buildHostSelection(state);

    final fileEntries = _files.map((f) => AntdFileEntry(
      name: f['name'] ?? '',
      isDir: f['is_dir'] == true,
      size: f['size'] as int?,
      modifiedTime: f['modified_time']?.toString(),
      extra: f,
    )).toList();

    return Scaffold(body: Column(children: [
      // Breadcrumb toolbar
      AntdToolbar(height: 44, bordered: true, spacing: 4, leading: [
        AntdButton(size: AntdSize.small, icon: Icons.arrow_back,
            onPressed: _backHistory.isEmpty ? null : _goBack),
        AntdButton(size: AntdSize.small, icon: Icons.arrow_forward,
            onPressed: _forwardHistory.isEmpty ? null : _goForward),
        AntdButton(size: AntdSize.small, icon: Icons.arrow_upward,
            onPressed: _currentPath == '/' ? null : _navigateUp),
        AntdButton(size: AntdSize.small, icon: Icons.history,
            onPressed: _showHistoryBottomSheet),
        AntdButton(size: AntdSize.small, icon: _sftpFavorites.contains(_currentPath) ? Icons.star : Icons.star_border,
            onPressed: _showFavoritesBottomSheet),
      ], trailing: [
        SizedBox(width: 200, child: AntdInput(
          controller: _pathController,
          placeholder: _currentPath,
          prefixIcon: Icons.folder_outlined,
          onSubmitted: (v) => _goToPath(v),
          size: AntdSize.small,
        )),
        AntdButton(size: AntdSize.small, icon: Icons.edit_outlined,
            onPressed: _showPathDialog),
        AntdDropdown<String>(items: [
          const AntdDropdownItem(value: 'file', label: '\u65b0\u5efa\u6587\u4ef6', icon: Icons.note_add_outlined),
          const AntdDropdownItem(value: 'folder', label: '\u65b0\u5efa\u6587\u4ef6\u5939', icon: Icons.create_new_folder_outlined),
        ], onSelected: (v) {
          if (v == 'file') _showCreateDialog(isDir: false);
          else _showCreateDialog(isDir: true);
        }, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.add, size: 18, color: AntdTokens.primary))),
        AntdButton(size: AntdSize.small, icon: Icons.refresh, onPressed: _loadFiles),
        AntdButton(size: AntdSize.small, icon: Icons.close, danger: true,
            onPressed: () => setState(() => _selectedHost = null)),
      ]),

      // File list
      Expanded(child: AntdFileList(
        files: fileEntries,
        loading: _isLoading,
        emptyText: Translation.getText(state.locale, 'sftp.emptyFolder'),
        onDirTap: (e) => _navigateInto(e.extra as Map<String, dynamic>),
        actions: (entry) => [
          if (!entry.isDir) const AntdActionMenuItem(key: 'download', label: '\u4e0b\u8f7d', icon: Icons.download),
          const AntdActionMenuItem(key: 'rename', label: '\u91cd\u547d\u540d', icon: Icons.edit),
          const AntdActionMenuItem(key: 'delete', label: '\u5220\u9664', icon: Icons.delete, danger: true),
        ],
        onAction: (key, entry) {
          final f = entry.extra as Map<String, dynamic>;
          switch (key) {
            case 'download':
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('\u79fb\u52a8\u7aef\u6682\u672a\u5b9e\u73b0\u4e0b\u8f7d: ${f['name']}')));
            case 'rename':
              _showRenameDialog(f);
            case 'delete':
              _confirmDelete(f);
          }
        },
      )),
    ]));
  }
}
