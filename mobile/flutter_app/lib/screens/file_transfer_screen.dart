import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  void _selectHost(Host host) {
    setState(() {
      _selectedHost = host;
      _currentPath = '/';
      _files = [];
      _backHistory.clear();
      _forwardHistory.clear();
    });
    _loadFiles();
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
    if (normalized == _currentPath) return;
    setState(() {
      if (addHistory) { _backHistory.add(_currentPath); _forwardHistory.clear(); }
      _currentPath = normalized.startsWith('/') ? normalized : '/$normalized';
    });
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
    setState(() { _forwardHistory.add(_currentPath); _currentPath = _backHistory.removeLast(); });
    _loadFiles();
  }

  void _goForward() {
    if (_forwardHistory.isEmpty) return;
    setState(() { _backHistory.add(_currentPath); _currentPath = _forwardHistory.removeLast(); });
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
      ], trailing: [
        SizedBox(width: 200, child: AntdInput(
          controller: TextEditingController(text: _currentPath),
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
