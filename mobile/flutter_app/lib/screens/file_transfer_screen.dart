import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/antd_tokens.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/sftp_service.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

class FileTransferScreen extends StatefulWidget {
  const FileTransferScreen({
    super.key,
    this.initialHostId,
    this.singlePane = false,
    this.lockInitialHost = false,
    this.initialPath,
  });

  final int? initialHostId;
  final bool singlePane;
  final bool lockInitialHost;
  final String? initialPath;

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _PaneData {
  Host? host;
  String path = '/';
  List<Map<String, dynamic>> files = [];
  List<String> history = [];
  List<String> favorites = [];
  final List<String> back = [];
  final List<String> forward = [];
  Set<String> selected = {};
  final TextEditingController pathController = TextEditingController(text: '/');
  bool loading = false;

  void dispose() => pathController.dispose();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  final _left = _PaneData();
  final _right = _PaneData();
  final List<AntdUploadTask> _tasks = [];
  SftpService? _service;
  bool _initialHostScheduled = false;

  SftpService get service => _service!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service ??= SftpService(context.read<AppState>().apiService);
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  String _t(String key, [Map<String, Object> values = const {}]) {
    var value = Translation.getText(context.read<AppState>().locale, key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AntdTokens.error : null,
    ));
  }

  String _join(String directory, String name) {
    if (directory == '/') return '/$name';
    return '${directory.replaceFirst(RegExp(r'/+$'), '')}/$name';
  }

  Future<void> _selectHost(
    _PaneData pane,
    Host? host, {
    String? initialPath,
  }) async {
    final nextPath =
        initialPath != null && initialPath.startsWith('/') ? initialPath : '/';
    setState(() {
      pane.host = host;
      pane.path = nextPath;
      pane.pathController.text = nextPath;
      pane.files = [];
      pane.history = [];
      pane.favorites = [];
      pane.back.clear();
      pane.forward.clear();
      pane.selected.clear();
    });
    if (host == null) return;
    await Future.wait([_loadBookmarks(pane), _loadFiles(pane)]);
  }

  Future<void> _loadFiles(_PaneData pane) async {
    final host = pane.host;
    if (host == null) return;
    setState(() => pane.loading = true);
    try {
      final listing = await service.list('${host.id}', pane.path);
      if (!mounted || pane.host?.id != host.id) return;
      setState(() {
        pane.path = listing.cwd;
        pane.pathController.text = listing.cwd;
        pane.files = listing.files;
        pane.selected.removeWhere(
          (name) => !listing.files.any((file) => file['name'] == name),
        );
      });
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted && pane.host?.id == host.id) {
        setState(() => pane.loading = false);
      }
    }
  }

  Future<void> _loadBookmarks(_PaneData pane) async {
    final host = pane.host;
    if (host == null) return;
    try {
      final result = await service.bookmarks('${host.id}');
      if (!mounted || pane.host?.id != host.id) return;
      setState(() {
        pane.history = result.history;
        pane.favorites = result.favorites;
      });
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<void> _saveBookmarks(_PaneData pane) async {
    final host = pane.host;
    if (host == null) return;
    try {
      await service.saveBookmarks(
        '${host.id}',
        pane.history,
        pane.favorites,
      );
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<void> _goTo(_PaneData pane, String path, {bool track = true}) async {
    var next = path.trim();
    if (next.isEmpty) next = '/';
    if (!next.startsWith('/')) next = '/$next';
    if (next == pane.path) return;
    setState(() {
      if (track) {
        pane.back.add(pane.path);
        pane.forward.clear();
      }
      pane.path = next;
      pane.pathController.text = next;
      pane.selected.clear();
      pane.history.remove(next);
      pane.history.insert(0, next);
      if (pane.history.length > 15) {
        pane.history.removeRange(15, pane.history.length);
      }
    });
    unawaited(_saveBookmarks(pane));
    await _loadFiles(pane);
  }

  void _goBack(_PaneData pane) {
    if (pane.back.isEmpty) return;
    final next = pane.back.removeLast();
    pane.forward.add(pane.path);
    _goTo(pane, next, track: false);
  }

  void _goForward(_PaneData pane) {
    if (pane.forward.isEmpty) return;
    final next = pane.forward.removeLast();
    pane.back.add(pane.path);
    _goTo(pane, next, track: false);
  }

  void _goUp(_PaneData pane) {
    if (pane.path == '/') return;
    final parts = pane.path.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    _goTo(pane, parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  Future<String?> _prompt({
    required String title,
    String initialValue = '',
    String? placeholder,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(title),
        width: 420,
        okText: _t('common.confirm'),
        cancelText: _t('common.cancel'),
        onOk: () => Navigator.of(dialogContext).pop(controller.text.trim()),
        child: AntdInput(
          controller: controller,
          placeholder: placeholder,
          autofocus: true,
          onSubmitted: (_) =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
        ),
      ),
    );
    controller.dispose();
    return result == null || result.isEmpty ? null : result;
  }

  Future<bool> _confirm(String title, String content,
      {bool danger = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AntdModal(
            title: Text(title),
            width: 420,
            danger: danger,
            okText: _t('common.confirm'),
            cancelText: _t('common.cancel'),
            onOk: () => Navigator.of(dialogContext).pop(true),
            child: Text(content),
          ),
        ) ==
        true;
  }

  Future<void> _create(_PaneData pane, bool directory) async {
    final host = pane.host;
    if (host == null) return;
    final name = await _prompt(
      title: _t(directory ? 'sftp.newFolder' : 'sftp.newFile'),
      placeholder: _t(directory ? 'sftp.folderName' : 'sftp.fileName'),
    );
    if (name == null) return;
    try {
      final path = _join(pane.path, name);
      directory
          ? await service.createDirectory('${host.id}', path)
          : await service.createFile('${host.id}', path);
      _message(_t('sftp.created', {'type': name}));
      await _loadFiles(pane);
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<void> _rename(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final oldName = file['name']?.toString() ?? '';
    final name = await _prompt(
      title: _t('sftp.rename'),
      initialValue: oldName,
      placeholder: _t('sftp.newName'),
    );
    if (name == null || name == oldName) return;
    try {
      await service.rename(
        '${host.id}',
        _join(pane.path, oldName),
        _join(pane.path, name),
      );
      _message(_t('sftp.renamed'));
      await _loadFiles(pane);
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<void> _delete(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    if (!await _confirm(
      _t('common.confirmDelete'),
      '${_t('sftp.deleteConfirm')}\n$name',
      danger: true,
    )) {
      return;
    }
    try {
      await service.delete('${host.id}', _join(pane.path, name));
      _message(_t('sftp.deleted'));
      await _loadFiles(pane);
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<AntdConflictStrategy?> _resolveConflict(String name) {
    return showDialog<AntdConflictStrategy>(
      context: context,
      builder: (dialogContext) => AntdConflictModal(
        fileName: name,
        onResolve: (strategy, _) => Navigator.of(dialogContext).pop(strategy),
      ),
    );
  }

  String _keepBothName(String name, List<Map<String, dynamic>> files) {
    final dot = name.lastIndexOf('.');
    final hasExtension = dot > 0;
    final stem = hasExtension ? name.substring(0, dot) : name;
    final extension = hasExtension ? name.substring(dot) : '';
    final existing = files.map((file) => file['name']?.toString()).toSet();
    var index = 1;
    var candidate = '$stem ($index)$extension';
    while (existing.contains(candidate)) {
      index++;
      candidate = '$stem ($index)$extension';
    }
    return candidate;
  }

  Future<({String name, bool overwrite})?> _destination(
    String requested,
    _PaneData pane,
  ) async {
    if (!pane.files.any((file) => file['name'] == requested)) {
      return (name: requested, overwrite: false);
    }
    final strategy = await _resolveConflict(requested);
    if (strategy == null || strategy == AntdConflictStrategy.skip) return null;
    if (strategy == AntdConflictStrategy.overwrite) {
      return (name: requested, overwrite: true);
    }
    return (name: _keepBothName(requested, pane.files), overwrite: false);
  }

  void _addTask(String id, String name, int total) {
    setState(() => _tasks.add(AntdUploadTask(
          id: id,
          name: name,
          totalBytes: total,
        )));
  }

  void _updateTask(
    String id, {
    int? total,
    int? written,
    AntdUploadStatus? status,
  }) {
    if (!mounted) return;
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index < 0) return;
    setState(() => _tasks[index] = _tasks[index].copyWith(
          totalBytes: total,
          uploadedBytes: written,
          status: status,
        ));
  }

  Future<void> _upload(_PaneData pane) async {
    final host = pane.host;
    if (host == null) return;
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withReadStream: true,
    );
    if (result == null) return;

    for (var i = 0; i < result.files.length; i++) {
      final platformFile = result.files[i];
      final xFile = result.xFiles[i];
      final destination = await _destination(platformFile.name, pane);
      if (destination == null) continue;
      final id = 'upload-${DateTime.now().microsecondsSinceEpoch}-$i';
      _addTask(id, destination.name, platformFile.size);
      try {
        await service.upload(
          '${host.id}',
          pane.path,
          SftpUploadSource(
            name: destination.name,
            size: platformFile.size,
            openRead: xFile.openRead,
          ),
          overwrite: destination.overwrite,
          onProgress: (progress) => _updateTask(
            id,
            total: progress.total,
            written: progress.written,
          ),
        );
        _updateTask(
          id,
          written: platformFile.size,
          status: AntdUploadStatus.success,
        );
        _message(_t('sftp.uploadSuccess', {'name': destination.name}));
      } catch (error) {
        _updateTask(id, status: AntdUploadStatus.failed);
        _message('$error', error: true);
      }
    }
    await _loadFiles(pane);
  }

  Future<void> _download(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    final downloadName = file['is_dir'] == true ? '$name.tar' : name;
    final id = 'download-${DateTime.now().microsecondsSinceEpoch}';
    final knownSize = (file['size'] as num?)?.toInt() ?? 0;
    _addTask(id, downloadName, knownSize);
    try {
      final bytes =
          await service.download('${host.id}', _join(pane.path, name));
      _updateTask(id, total: bytes.length, written: bytes.length);
      final path = await FilePicker.saveFile(
        dialogTitle: _t('sftp.download'),
        fileName: downloadName,
        bytes: bytes,
      );
      _updateTask(
        id,
        total: bytes.length,
        written: bytes.length,
        status: path == null
            ? AntdUploadStatus.cancelled
            : AntdUploadStatus.success,
      );
      if (path != null) {
        _message(_t('sftp.downloadSuccess', {'name': downloadName}));
      }
    } catch (error) {
      _updateTask(id, status: AntdUploadStatus.failed);
      _message('$error', error: true);
    }
  }

  Future<void> _edit(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    try {
      final bytes = await service.readForEditor(
        '${host.id}',
        _join(pane.path, name),
      );
      if (!mounted) return;
      final controller = TextEditingController(
        text: utf8.decode(bytes, allowMalformed: true),
      );
      final edited = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AntdModal(
          title: Text(name),
          width: 900,
          bodyMaxHeight: 620,
          okText: _t('common.save'),
          cancelText: _t('common.cancel'),
          onOk: () => Navigator.of(dialogContext).pop(controller.text),
          child: SizedBox(
            height: 480,
            child: TextField(
              controller: controller,
              expands: true,
              minLines: null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(
                fontFamily: 'TermiScope Mono',
                fontSize: 13,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: AntdTokens.borderColor(context)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AntdTokens.primary),
                ),
              ),
            ),
          ),
        ),
      );
      controller.dispose();
      if (edited == null) return;
      final content = Uint8List.fromList(utf8.encode(edited));
      final id = 'save-${DateTime.now().microsecondsSinceEpoch}';
      _addTask(id, name, content.length);
      await service.upload(
        '${host.id}',
        pane.path,
        SftpUploadSource.bytes(name, content),
        overwrite: true,
        onProgress: (progress) => _updateTask(
          id,
          total: progress.total,
          written: progress.written,
        ),
      );
      _updateTask(
        id,
        written: content.length,
        status: AntdUploadStatus.success,
      );
      _message(_t('common.saveSuccess'));
      await _loadFiles(pane);
    } catch (error) {
      _message('$error', error: true);
    }
  }

  Future<void> _transferOne(
    _PaneData source,
    _PaneData destination,
    Map<String, dynamic> file,
  ) async {
    if (source.host == null || destination.host == null) {
      _message(_t('sftp.selectBothHosts'), error: true);
      return;
    }
    final originalName = file['name']?.toString() ?? '';
    final target = await _destination(originalName, destination);
    if (target == null) return;
    final total = (file['size'] as num?)?.toInt() ?? 0;
    final id = 'transfer-${DateTime.now().microsecondsSinceEpoch}';
    _addTask(
        id,
        '${source.host!.name} -> ${destination.host!.name}: ${target.name}',
        total);
    try {
      await service.transfer(
        sourceHostId: '${source.host!.id}',
        destinationHostId: '${destination.host!.id}',
        sourcePath: _join(source.path, originalName),
        destinationPath: destination.path,
        destinationName: target.name,
        overwrite: target.overwrite,
        onEvent: (event) {
          if (event['type'] == 'start') {
            _updateTask(id, total: (event['total_size'] as num?)?.toInt());
          } else if (event['type'] == 'progress') {
            _updateTask(
              id,
              total: (event['total'] as num?)?.toInt(),
              written: (event['transferred'] as num?)?.toInt(),
            );
          }
        },
      );
      final resolvedTotal =
          _tasks.firstWhere((task) => task.id == id).totalBytes;
      _updateTask(
        id,
        written: resolvedTotal,
        status: AntdUploadStatus.success,
      );
      _message(_t('sftp.transferSuccess', {'name': target.name}));
      await _loadFiles(destination);
    } catch (error) {
      _updateTask(id, status: AntdUploadStatus.failed);
      _message('$error', error: true);
    }
  }

  Future<void> _bulkTransfer(_PaneData source, _PaneData destination) async {
    if (source.selected.isEmpty) return;
    if (destination.host == null) {
      _message(_t('sftp.selectBothHosts'), error: true);
      return;
    }
    final selected = source.files
        .where((file) => source.selected.contains(file['name']))
        .toList();
    if (!await _confirm(
      _t('sftp.bulkTransfer'),
      _t('sftp.confirmBulkTransfer', {'count': selected.length}),
    )) {
      return;
    }
    setState(() => source.selected.clear());
    for (final file in selected) {
      await _transferOne(source, destination, file);
    }
  }

  Future<void> _toggleFavorite(_PaneData pane) async {
    setState(() {
      if (pane.favorites.contains(pane.path)) {
        pane.favorites.remove(pane.path);
      } else {
        pane.favorites.add(pane.path);
      }
    });
    await _saveBookmarks(pane);
  }

  Future<void> _showPaths(_PaneData pane) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('sftp.goToPath'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AntdButton(
                      type: AntdButtonType.text,
                      size: AntdSize.small,
                      icon: pane.favorites.contains(pane.path)
                          ? Icons.star
                          : Icons.star_border,
                      onPressed: () async {
                        await _toggleFavorite(pane);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                    ),
                  ],
                ),
              ),
              const AntdDivider(),
              Expanded(
                child: ListView(
                  children: [
                    for (final path in pane.favorites)
                      ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.star, color: AntdTokens.warning),
                        title: Text(path),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _goTo(pane, path);
                        },
                      ),
                    for (final path in pane.history)
                      if (!pane.favorites.contains(path))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(path),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _goTo(pane, path);
                          },
                        ),
                    if (pane.history.isEmpty && pane.favorites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: AntdEmpty(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: AntdButton(
        size: AntdSize.small,
        type: primary ? AntdButtonType.primary : AntdButtonType.defaultType,
        icon: icon,
        onPressed: onPressed,
      ),
    );
  }

  Widget _paneToolbar(_PaneData pane, _PaneData other) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _iconButton(
                    tooltip: _t('sftp.navBack'),
                    icon: Icons.arrow_back,
                    onPressed: pane.back.isEmpty ? null : () => _goBack(pane),
                  ),
                  const SizedBox(width: 4),
                  _iconButton(
                    tooltip: _t('sftp.navForward'),
                    icon: Icons.arrow_forward,
                    onPressed:
                        pane.forward.isEmpty ? null : () => _goForward(pane),
                  ),
                  const SizedBox(width: 4),
                  _iconButton(
                    tooltip: _t('sftp.navUp'),
                    icon: Icons.arrow_upward,
                    onPressed: pane.path == '/' ? null : () => _goUp(pane),
                  ),
                  const SizedBox(width: 4),
                  _iconButton(
                    tooltip: _t('sftp.goToPath'),
                    icon: Icons.history,
                    onPressed: () => _showPaths(pane),
                  ),
                  const SizedBox(width: 4),
                  _iconButton(
                    tooltip: _t('sftp.upload'),
                    icon: Icons.upload,
                    primary: true,
                    onPressed: () => _upload(pane),
                  ),
                  const SizedBox(width: 4),
                  AntdDropdown<String>(
                    items: [
                      AntdDropdownItem(
                        value: 'file',
                        label: _t('sftp.newFile'),
                        icon: Icons.note_add_outlined,
                      ),
                      AntdDropdownItem(
                        value: 'folder',
                        label: _t('sftp.newFolder'),
                        icon: Icons.create_new_folder_outlined,
                      ),
                    ],
                    onSelected: (value) => _create(pane, value == 'folder'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.add,
                        size: 18,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _iconButton(
                    tooltip: _t('common.refresh'),
                    icon: Icons.refresh,
                    onPressed: () => _loadFiles(pane),
                  ),
                  if (other.host != null && pane.selected.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    AntdButton(
                      size: AntdSize.small,
                      type: AntdButtonType.primary,
                      icon: Icons.send_outlined,
                      onPressed: () => _bulkTransfer(pane, other),
                      child: Text(
                          '${_t('sftp.bulkTransfer')} (${pane.selected.length})'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: AntdInput(
              controller: pane.pathController,
              size: AntdSize.small,
              prefixIcon: Icons.folder_outlined,
              placeholder: _t('sftp.pathPlaceholder'),
              onSubmitted: (path) => _goTo(pane, path),
            ),
          ),
        ],
      ),
    );
  }

  List<AntdActionMenuItem> _actions(
          _PaneData pane, _PaneData other, AntdFileEntry entry) =>
      [
        AntdActionMenuItem(
          key: 'download',
          label: _t('sftp.download'),
          icon: Icons.download,
        ),
        if (!entry.isDir)
          AntdActionMenuItem(
            key: 'edit',
            label: _t('sftp.edit'),
            icon: Icons.edit_note,
          ),
        if (other.host != null)
          AntdActionMenuItem(
            key: 'transfer',
            label: _t('sftp.sendTo', {'name': other.host!.name}),
            icon: Icons.send_outlined,
          ),
        AntdActionMenuItem(
          key: 'rename',
          label: _t('sftp.rename'),
          icon: Icons.drive_file_rename_outline,
        ),
        AntdActionMenuItem(
          key: 'delete',
          label: _t('sftp.delete'),
          icon: Icons.delete_outline,
          danger: true,
        ),
      ];

  Widget _pane(_PaneData pane, _PaneData other, List<Host> hosts) {
    return LayoutBuilder(builder: (context, constraints) {
      final compactHeader = constraints.maxWidth < 430;
      final selector = AntdSelect<int>(
        value: pane.host?.id,
        placeholder: _t('sftp.selectHost'),
        allowClear: true,
        options: hosts
            .map((host) => AntdSelectOption<int>(
                  value: host.id,
                  label: '${host.name}  ${host.host}',
                  icon: Icons.dns_outlined,
                ))
            .toList(),
        onChanged: (id) => _selectHost(
          pane,
          id == null ? null : hosts.firstWhere((host) => host.id == id),
        ),
      );
      return Container(
        decoration: BoxDecoration(
          color: AntdTokens.containerColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AntdTokens.borderSecondaryColor(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (!(widget.lockInitialHost && pane == _left))
              Padding(
                padding: const EdgeInsets.all(12),
                child: compactHeader
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          selector,
                          const SizedBox(height: 8),
                          AntdButton(
                            block: true,
                            size: AntdSize.small,
                            type: AntdButtonType.primary,
                            icon: Icons.swap_horiz,
                            onPressed:
                                pane.selected.isEmpty || other.host == null
                                    ? null
                                    : () => _bulkTransfer(pane, other),
                            child: Text(
                              '${_t('sftp.bulkTransfer')} (${pane.selected.length})',
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: selector),
                          const SizedBox(width: 8),
                          AntdButton(
                            size: AntdSize.small,
                            type: AntdButtonType.primary,
                            icon: Icons.swap_horiz,
                            onPressed:
                                pane.selected.isEmpty || other.host == null
                                    ? null
                                    : () => _bulkTransfer(pane, other),
                            child: Text(
                              '${_t('sftp.bulkTransfer')} (${pane.selected.length})',
                            ),
                          ),
                        ],
                      ),
              ),
            if (!(widget.lockInitialHost && pane == _left))
              Divider(
                  height: 1, color: AntdTokens.borderSecondaryColor(context)),
            Expanded(
              child: pane.host == null
                  ? Center(
                      child: AntdEmpty(description: _t('sftp.selectHost')),
                    )
                  : Column(
                      children: [
                        _paneToolbar(pane, other),
                        Expanded(
                          child: AntdFileList(
                            files: pane.files
                                .map((file) => AntdFileEntry(
                                      name: file['name']?.toString() ?? '',
                                      isDir: file['is_dir'] == true,
                                      size: (file['size'] as num?)?.toInt(),
                                      modifiedTime:
                                          file['mod_time']?.toString(),
                                      extra: file,
                                    ))
                                .toList(),
                            loading: pane.loading,
                            emptyText: _t('sftp.emptyFolder'),
                            selectedNames: pane.selected,
                            onSelectionChanged: (selection) =>
                                setState(() => pane.selected = selection),
                            onDirTap: (entry) =>
                                _goTo(pane, _join(pane.path, entry.name)),
                            onFileTap: (entry) => _edit(
                                pane, entry.extra as Map<String, dynamic>),
                            actions: (entry) => _actions(pane, other, entry),
                            onAction: (action, entry) {
                              final file = entry.extra as Map<String, dynamic>;
                              switch (action) {
                                case 'download':
                                  _download(pane, file);
                                case 'edit':
                                  _edit(pane, file);
                                case 'transfer':
                                  _transferOne(pane, other, file);
                                case 'rename':
                                  _rename(pane, file);
                                case 'delete':
                                  _delete(pane, file);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    });
  }

  Widget _divider(bool mobile) => SizedBox(
        width: mobile ? null : 32,
        height: mobile ? 28 : null,
        child: Center(
          child: Transform.rotate(
            angle: mobile ? 1.5708 : 0,
            child: Icon(
              Icons.swap_horiz,
              size: 20,
              color: AntdTokens.secondaryTextColor(context),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hosts =
        state.hosts.where((host) => host.hostType != 'monitor_only').toList();
    final initialHostId = widget.initialHostId;
    if (!_initialHostScheduled && initialHostId != null) {
      final matches = hosts.where((host) => host.id == initialHostId);
      if (matches.isNotEmpty) {
        _initialHostScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _selectHost(
              _left,
              matches.first,
              initialPath: widget.initialPath,
            );
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final mobile = constraints.maxWidth <= 768;
                if (widget.singlePane) {
                  return _pane(_left, _right, hosts);
                }
                if (!mobile) {
                  return Row(
                    children: [
                      Expanded(child: _pane(_left, _right, hosts)),
                      _divider(false),
                      Expanded(child: _pane(_right, _left, hosts)),
                    ],
                  );
                }
                final panelHeight =
                    constraints.maxHeight.clamp(480.0, 560.0).toDouble();
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(
                          height: panelHeight,
                          child: _pane(_left, _right, hosts)),
                      _divider(true),
                      SizedBox(
                          height: panelHeight,
                          child: _pane(_right, _left, hosts)),
                    ],
                  ),
                );
              }),
            ),
            if (_tasks.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: AntdUploadProgressDock(
                  tasks: _tasks.reversed.take(5).toList().reversed.toList(),
                  expanded: true,
                  title: _t('sftp.transferQueue'),
                  onClear: () => setState(() => _tasks.removeWhere(
                        (task) => task.status != AntdUploadStatus.uploading,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
