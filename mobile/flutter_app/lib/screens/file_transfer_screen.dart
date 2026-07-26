import 'dart:async';
import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool dragging = false;

  void dispose() => pathController.dispose();
}

class _SftpClipboard {
  const _SftpClipboard({
    required this.hostId,
    required this.paths,
    required this.type,
  });

  final int hostId;
  final List<String> paths;
  final String type;
}

class _EditorTabData {
  _EditorTabData({
    required this.key,
    required this.pane,
    required this.hostId,
    required this.path,
    required this.name,
    required String content,
  })  : controller = TextEditingController(text: content),
        savedContent = content;

  final String key;
  final _PaneData pane;
  final int hostId;
  final String path;
  final String name;
  final TextEditingController controller;
  String savedContent;
  bool dirty = false;
  bool saving = false;
  bool loading = false;

  void dispose() => controller.dispose();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  final _left = _PaneData();
  final _right = _PaneData();
  final List<AntdUploadTask> _tasks = [];
  final Map<String, SftpCancelToken> _taskCancels = {};
  final Map<String, Future<void> Function()> _taskRetries = {};
  SftpService? _service;
  bool _initialHostScheduled = false;
  _SftpClipboard? _clipboard;
  final List<_EditorTabData> _editorTabs = [];
  String? _activeEditorKey;
  bool _editorMinimized = false;
  bool _editorMaximized = false;

  SftpService get service => _service!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service ??= SftpService(context.read<AppState>().apiService);
  }

  @override
  void dispose() {
    for (final token in _taskCancels.values) {
      token.cancel();
    }
    for (final tab in _editorTabs) {
      tab.dispose();
    }
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

  void _restartTask(String id) {
    _updateTask(
      id,
      written: 0,
      status: AntdUploadStatus.uploading,
    );
  }

  void _cancelTask(String id) {
    _taskCancels[id]?.cancel();
    _updateTask(id, status: AntdUploadStatus.cancelled);
  }

  Future<void> _retryTask(String id) async {
    final retry = _taskRetries[id];
    if (retry == null) return;
    _restartTask(id);
    await retry();
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

  Future<void> _runUploadTask({
    required String id,
    required _PaneData pane,
    required int hostId,
    required String remotePath,
    required SftpUploadSource source,
    required bool overwrite,
  }) async {
    final token = SftpCancelToken();
    _taskCancels[id] = token;
    _taskRetries[id] = () => _runUploadTask(
          id: id,
          pane: pane,
          hostId: hostId,
          remotePath: remotePath,
          source: source,
          overwrite: overwrite,
        );
    try {
      await service.upload(
        '$hostId',
        remotePath,
        source,
        overwrite: overwrite,
        cancelToken: token,
        onProgress: (progress) => _updateTask(
          id,
          total: progress.total,
          written: progress.written,
        ),
      );
      if (token.isCancelled) return;
      _updateTask(
        id,
        written: source.size,
        status: AntdUploadStatus.success,
      );
      _message(_t('sftp.uploadSuccess', {'name': source.name}));
      if (pane.host?.id == hostId) await _loadFiles(pane);
    } catch (error) {
      _updateTask(
        id,
        status: token.isCancelled
            ? AntdUploadStatus.cancelled
            : AntdUploadStatus.failed,
      );
      if (!token.isCancelled) _message('$error', error: true);
    } finally {
      if (identical(_taskCancels[id], token)) _taskCancels.remove(id);
    }
  }

  Future<void> _uploadSources(
    _PaneData pane,
    List<SftpUploadSource> sources,
  ) async {
    final host = pane.host;
    if (host == null) return;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      final destination = await _destination(source.name, pane);
      if (destination == null) continue;
      final id = 'upload-${DateTime.now().microsecondsSinceEpoch}-$i';
      final resolvedSource = SftpUploadSource(
        name: destination.name,
        size: source.size,
        openRead: source.openRead,
      );
      _addTask(id, destination.name, source.size);
      await _runUploadTask(
        id: id,
        pane: pane,
        hostId: host.id,
        remotePath: pane.path,
        source: resolvedSource,
        overwrite: destination.overwrite,
      );
    }
  }

  Future<void> _upload(_PaneData pane) async {
    final result = await FilePicker.pickFiles();
    if (result == null) return;
    await _uploadSources(
      pane,
      List.generate(result.files.length, (index) {
        final platformFile = result.files[index];
        return SftpUploadSource(
          name: platformFile.name,
          size: platformFile.size,
          openRead: platformFile.readAsByteStream,
        );
      }),
    );
  }

  Future<void> _uploadDropped(
    _PaneData pane,
    List<DropItem> items,
  ) async {
    final files = <DropItem>[];
    void collect(DropItem item) {
      if (item is DropItemDirectory) {
        for (final child in item.children) {
          collect(child);
        }
      } else {
        files.add(item);
      }
    }

    for (final item in items) {
      collect(item);
    }
    final sources = <SftpUploadSource>[];
    for (final file in files) {
      sources.add(SftpUploadSource(
        name: file.name,
        size: await file.length(),
        openRead: file.openRead,
      ));
    }
    await _uploadSources(pane, sources);
  }

  Future<void> _download(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    final downloadName = file['is_dir'] == true ? '$name.tar' : name;
    final id = 'download-${DateTime.now().microsecondsSinceEpoch}';
    final knownSize = (file['size'] as num?)?.toInt() ?? 0;
    _addTask(id, downloadName, knownSize);
    await _runDownloadTask(
      id: id,
      hostId: host.id,
      remotePath: _join(pane.path, name),
      downloadName: downloadName,
    );
  }

  Future<void> _runDownloadTask({
    required String id,
    required int hostId,
    required String remotePath,
    required String downloadName,
  }) async {
    final token = SftpCancelToken();
    _taskCancels[id] = token;
    _taskRetries[id] = () => _runDownloadTask(
          id: id,
          hostId: hostId,
          remotePath: remotePath,
          downloadName: downloadName,
        );
    try {
      final bytes = await service.download(
        '$hostId',
        remotePath,
        cancelToken: token,
      );
      if (token.isCancelled) return;
      _updateTask(id, total: bytes.length, written: bytes.length);
      final path = await FilePicker.saveFile(
        dialogTitle: _t('sftp.download'),
        fileName: downloadName,
        bytes: bytes,
      );
      if (token.isCancelled) return;
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
      _updateTask(
        id,
        status: token.isCancelled
            ? AntdUploadStatus.cancelled
            : AntdUploadStatus.failed,
      );
      if (!token.isCancelled) _message('$error', error: true);
    } finally {
      if (identical(_taskCancels[id], token)) _taskCancels.remove(id);
    }
  }

  Future<void> _edit(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    final path = _join(pane.path, name);
    final key = '${host.id}:$path';
    final existing = _editorTabs.where((tab) => tab.key == key);
    if (existing.isNotEmpty) {
      setState(() {
        _activeEditorKey = key;
        _editorMinimized = false;
      });
      return;
    }
    try {
      final bytes = await service.readForEditor(
        '${host.id}',
        path,
      );
      if (!mounted) return;
      final tab = _EditorTabData(
        key: key,
        pane: pane,
        hostId: host.id,
        path: path,
        name: name,
        content: utf8.decode(bytes, allowMalformed: true),
      );
      setState(() {
        _editorTabs.add(tab);
        _activeEditorKey = key;
        _editorMinimized = false;
      });
    } catch (error) {
      _message('$error', error: true);
    }
  }

  _EditorTabData? get _activeEditor {
    for (final tab in _editorTabs) {
      if (tab.key == _activeEditorKey) return tab;
    }
    return null;
  }

  String _parentPath(String path) {
    final index = path.lastIndexOf('/');
    if (index <= 0) return '/';
    return path.substring(0, index);
  }

  Future<bool> _saveEditorTab(_EditorTabData tab) async {
    if (!tab.dirty || tab.saving) return true;
    setState(() => tab.saving = true);
    final content = Uint8List.fromList(utf8.encode(tab.controller.text));
    final id = 'save-${DateTime.now().microsecondsSinceEpoch}';
    _addTask(id, tab.name, content.length);
    await _runUploadTask(
      id: id,
      pane: tab.pane,
      hostId: tab.hostId,
      remotePath: _parentPath(tab.path),
      source: SftpUploadSource.bytes(tab.name, content),
      overwrite: true,
    );
    final succeeded = _tasks.any(
        (task) => task.id == id && task.status == AntdUploadStatus.success);
    if (mounted && _editorTabs.contains(tab)) {
      setState(() {
        tab.saving = false;
        if (succeeded) {
          tab.savedContent = tab.controller.text;
          tab.dirty = false;
        }
      });
    }
    return succeeded;
  }

  Future<void> _refreshEditorTab(_EditorTabData tab) async {
    if (tab.dirty &&
        !await _confirm(
          _t('sftp.refreshFile'),
          _t('sftp.unsavedContent'),
        )) {
      return;
    }
    setState(() => tab.loading = true);
    try {
      final bytes = await service.readForEditor('${tab.hostId}', tab.path);
      if (!mounted || !_editorTabs.contains(tab)) return;
      final content = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        tab.controller.text = content;
        tab.savedContent = content;
        tab.dirty = false;
      });
    } catch (error) {
      _message('$error', error: true);
    } finally {
      if (mounted && _editorTabs.contains(tab)) {
        setState(() => tab.loading = false);
      }
    }
  }

  Future<String?> _confirmCloseEditor(_EditorTabData tab) {
    if (!tab.dirty) return Future.value('discard');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(_t('sftp.unsavedTitle')),
        width: 460,
        footer: [
          AntdButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('common.cancel')),
          ),
          AntdButton(
            danger: true,
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: Text(_t('sftp.unsavedLeave')),
          ),
          AntdButton(
            type: AntdButtonType.primary,
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(_t('common.save')),
          ),
        ],
        child: Text(_t('sftp.unsavedContent')),
      ),
    );
  }

  Future<bool> _closeEditorTab(String key) async {
    final index = _editorTabs.indexWhere((tab) => tab.key == key);
    if (index < 0) return true;
    final tab = _editorTabs[index];
    final choice = await _confirmCloseEditor(tab);
    if (choice == null) return false;
    if (choice == 'save' && !await _saveEditorTab(tab)) return false;
    if (!mounted) return false;
    setState(() {
      _editorTabs.remove(tab);
      tab.dispose();
      if (_activeEditorKey == key) {
        _activeEditorKey = _editorTabs.isEmpty
            ? null
            : _editorTabs[index.clamp(0, _editorTabs.length - 1)].key;
      }
    });
    return true;
  }

  Future<void> _closeAllEditors() async {
    for (final tab in List<_EditorTabData>.from(_editorTabs).reversed) {
      if (!await _closeEditorTab(tab.key)) return;
    }
  }

  Future<void> _findReplace(_EditorTabData tab) async {
    final find = TextEditingController();
    final replace = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(_t('sftp.searchReplace')),
        width: 480,
        okText: _t('common.confirm'),
        cancelText: _t('common.cancel'),
        onOk: () => Navigator.pop(
          dialogContext,
          (find.text, replace.text),
        ),
        child: Column(
          children: [
            AntdInput(controller: find, placeholder: _t('common.search')),
            const SizedBox(height: 8),
            AntdInput(controller: replace, placeholder: _t('sftp.replace')),
          ],
        ),
      ),
    );
    find.dispose();
    replace.dispose();
    if (result == null || result.$1.isEmpty) return;
    final next = tab.controller.text.replaceAll(result.$1, result.$2);
    setState(() {
      tab.controller.text = next;
      tab.dirty = next != tab.savedContent;
    });
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
    await _runTransferTask(
      id: id,
      sourcePane: source,
      destinationPane: destination,
      sourceHostId: source.host!.id,
      destinationHostId: destination.host!.id,
      sourcePath: _join(source.path, originalName),
      destinationPath: destination.path,
      destinationName: target.name,
      overwrite: target.overwrite,
    );
  }

  Future<void> _runTransferTask({
    required String id,
    required _PaneData sourcePane,
    required _PaneData destinationPane,
    required int sourceHostId,
    required int destinationHostId,
    required String sourcePath,
    required String destinationPath,
    required String destinationName,
    required bool overwrite,
    String type = 'copy',
  }) async {
    final token = SftpCancelToken();
    _taskCancels[id] = token;
    _taskRetries[id] = () => _runTransferTask(
          id: id,
          sourcePane: sourcePane,
          destinationPane: destinationPane,
          sourceHostId: sourceHostId,
          destinationHostId: destinationHostId,
          sourcePath: sourcePath,
          destinationPath: destinationPath,
          destinationName: destinationName,
          overwrite: overwrite,
          type: type,
        );
    try {
      await service.transfer(
        sourceHostId: '$sourceHostId',
        destinationHostId: '$destinationHostId',
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        destinationName: destinationName,
        overwrite: overwrite,
        type: type,
        cancelToken: token,
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
      if (token.isCancelled) return;
      final resolvedTotal =
          _tasks.firstWhere((task) => task.id == id).totalBytes;
      _updateTask(
        id,
        written: resolvedTotal,
        status: AntdUploadStatus.success,
      );
      _message(_t('sftp.transferSuccess', {'name': destinationName}));
      if (destinationPane.host?.id == destinationHostId) {
        await _loadFiles(destinationPane);
      }
      if (type == 'cut' && sourcePane.host?.id == sourceHostId) {
        await _loadFiles(sourcePane);
      }
    } catch (error) {
      _updateTask(
        id,
        status: token.isCancelled
            ? AntdUploadStatus.cancelled
            : AntdUploadStatus.failed,
      );
      if (!token.isCancelled) _message('$error', error: true);
    } finally {
      if (identical(_taskCancels[id], token)) _taskCancels.remove(id);
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

  Future<void> _bulkDownload(_PaneData pane) async {
    final selected = pane.files
        .where((file) => pane.selected.contains(file['name']))
        .toList();
    for (final file in selected) {
      await _download(pane, file);
    }
  }

  Future<void> _bulkDelete(_PaneData pane) async {
    final host = pane.host;
    if (host == null || pane.selected.isEmpty) return;
    final names = pane.selected.toList();
    if (!await _confirm(
      _t('common.confirmDelete'),
      _t('sftp.deleteSelectedConfirm', {'count': names.length}),
      danger: true,
    )) {
      return;
    }
    try {
      for (final name in names) {
        await service.delete('${host.id}', _join(pane.path, name));
      }
      setState(() => pane.selected.clear());
      _message(_t('sftp.deleted'));
      await _loadFiles(pane);
    } catch (error) {
      _message('$error', error: true);
    }
  }

  void _selectAll(_PaneData pane) {
    setState(() => pane.selected = pane.files
        .map((file) => file['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet());
  }

  void _invertSelection(_PaneData pane) {
    final all = pane.files
        .map((file) => file['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
    setState(() => pane.selected = all.difference(pane.selected));
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(1)} ${units[unit]}';
  }

  Future<void> _showProperties(_PaneData pane) async {
    final selected = pane.files
        .where((file) => pane.selected.contains(file['name']))
        .toList();
    if (selected.isEmpty) return;
    final directories = selected.where((file) => file['is_dir'] == true).length;
    final files = selected.length - directories;
    final total = selected.fold<int>(
      0,
      (sum, file) => sum + ((file['size'] as num?)?.toInt() ?? 0),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(_t('sftp.properties')),
        width: 500,
        showFooter: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_t('sftp.selectedFiles')}: ${selected.length}'),
            Text('${_t('sftp.files')}: $files'),
            Text('${_t('sftp.directories')}: $directories'),
            Text('${_t('sftp.totalSize')}: ${_formatBytes(total)}'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(
                  selected.map((file) => file['name']).join('\n'),
                  style: TextStyle(
                    fontSize: AntdTokens.fontSizeSM,
                    color: AntdTokens.secondaryTextColor(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearFinishedTasks() {
    final finished = _tasks
        .where((task) => task.status != AntdUploadStatus.uploading)
        .map((task) => task.id)
        .toSet();
    setState(() => _tasks.removeWhere((task) => finished.contains(task.id)));
    for (final id in finished) {
      _taskCancels.remove(id);
      _taskRetries.remove(id);
    }
  }

  String _baseName(String path) {
    final parts = path.split('/')..removeWhere((part) => part.isEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  void _setClipboard(_PaneData pane, Iterable<String> names, String type) {
    final host = pane.host;
    final paths = names.map((name) => _join(pane.path, name)).toList();
    if (host == null || paths.isEmpty) return;
    setState(() {
      _clipboard = _SftpClipboard(hostId: host.id, paths: paths, type: type);
    });
    _message(_t(
      type == 'cut' ? 'sftp.cutCount' : 'sftp.copyCount',
      {'count': paths.length},
    ));
  }

  Future<void> _paste(_PaneData pane, _PaneData other) async {
    final destinationHost = pane.host;
    final clipboard = _clipboard;
    if (destinationHost == null || clipboard == null) return;
    final sourcePane = pane.host?.id == clipboard.hostId
        ? pane
        : other.host?.id == clipboard.hostId
            ? other
            : other;
    var completed = 0;
    for (final sourcePath in clipboard.paths) {
      final originalName = _baseName(sourcePath);
      final target = await _destination(originalName, pane);
      if (target == null) continue;
      try {
        if (clipboard.hostId == destinationHost.id) {
          await service.paste(
            hostId: '${destinationHost.id}',
            source: sourcePath,
            destination: pane.path,
            type: clipboard.type,
            destinationName: target.name,
            overwrite: target.overwrite,
          );
          completed++;
        } else {
          final id = 'paste-${DateTime.now().microsecondsSinceEpoch}';
          final sourceName = sourcePane.host?.name ?? '${clipboard.hostId}';
          _addTask(
            id,
            '$sourceName -> ${destinationHost.name}: ${target.name}',
            0,
          );
          await _runTransferTask(
            id: id,
            sourcePane: sourcePane,
            destinationPane: pane,
            sourceHostId: clipboard.hostId,
            destinationHostId: destinationHost.id,
            sourcePath: sourcePath,
            destinationPath: pane.path,
            destinationName: target.name,
            overwrite: target.overwrite,
            type: clipboard.type,
          );
          final task = _tasks.firstWhere((task) => task.id == id);
          if (task.status == AntdUploadStatus.success) completed++;
        }
      } catch (error) {
        _message('${_t('sftp.failedToPaste')}: $error', error: true);
        break;
      }
    }
    if (completed > 0) {
      _message(_t('sftp.pasted'));
      await _loadFiles(pane);
      if (clipboard.type == 'cut' && completed == clipboard.paths.length) {
        setState(() => _clipboard = null);
        if (sourcePane.host?.id == clipboard.hostId && sourcePane != pane) {
          await _loadFiles(sourcePane);
        }
      }
    }
  }

  bool _isVideo(String name) {
    const extensions = {'mp4', 'webm', 'ogg', 'mov', 'avi', 'mkv'};
    return extensions.contains(name.split('.').last.toLowerCase());
  }

  bool _isMedia(String name) {
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'};
    return _isVideo(name) ||
        images.contains(name.split('.').last.toLowerCase());
  }

  Future<void> _preview(_PaneData pane, Map<String, dynamic> file) async {
    final host = pane.host;
    if (host == null) return;
    final name = file['name']?.toString() ?? '';
    final path = _join(pane.path, name);
    try {
      if (_isVideo(name)) {
        final api = context.read<AppState>().apiService;
        await showDialog<void>(
          context: context,
          builder: (_) => AntdMediaPreview(
            name: name,
            type: AntdMediaType.video,
            videoUrl: api.uri(
              '/api/sftp/download/${host.id}',
              {'path': path},
            ).toString(),
            videoHeaders: api.authenticatedHeaders(),
          ),
        );
      } else {
        final bytes = await service.download('${host.id}', path);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AntdMediaPreview(
            name: name,
            type: AntdMediaType.image,
            imageBytes: bytes,
          ),
        );
      }
    } catch (error) {
      _message('${_t('sftp.downloadFailed')}: $error', error: true);
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
                  _iconButton(
                    tooltip: _t('sftp.paste'),
                    icon: Icons.content_paste,
                    onPressed:
                        _clipboard == null ? null : () => _paste(pane, other),
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
                  if (pane.selected.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    AntdTag(
                      color: AntdTokens.primary,
                      label: _t(
                        'sftp.selected',
                        {'count': pane.selected.length},
                      ),
                    ),
                    const SizedBox(width: 4),
                    _iconButton(
                      tooltip: _t('sftp.downloadSelected'),
                      icon: Icons.download,
                      onPressed: () => _bulkDownload(pane),
                    ),
                    const SizedBox(width: 4),
                    _iconButton(
                      tooltip: _t('sftp.cutSelected'),
                      icon: Icons.content_cut,
                      onPressed: () =>
                          _setClipboard(pane, pane.selected, 'cut'),
                    ),
                    const SizedBox(width: 4),
                    _iconButton(
                      tooltip: _t('sftp.copySelected'),
                      icon: Icons.content_copy,
                      onPressed: () =>
                          _setClipboard(pane, pane.selected, 'copy'),
                    ),
                    const SizedBox(width: 4),
                    _iconButton(
                      tooltip: _t('sftp.deleteSelected'),
                      icon: Icons.delete_outline,
                      onPressed: () => _bulkDelete(pane),
                    ),
                  ],
                  const SizedBox(width: 4),
                  AntdDropdown<String>(
                    items: [
                      AntdDropdownItem(
                        value: 'all',
                        label: _t('sftp.selectAll'),
                        icon: Icons.select_all,
                      ),
                      AntdDropdownItem(
                        value: 'invert',
                        label: _t('sftp.invertSelection'),
                        icon: Icons.flip_to_back,
                      ),
                      AntdDropdownItem(
                        value: 'clear',
                        label: _t('sftp.clearSelection'),
                        icon: Icons.deselect,
                      ),
                      AntdDropdownItem(
                        value: 'properties',
                        label: _t('sftp.properties'),
                        icon: Icons.info_outline,
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'all':
                          _selectAll(pane);
                        case 'invert':
                          _invertSelection(pane);
                        case 'clear':
                          setState(() => pane.selected.clear());
                        case 'properties':
                          _showProperties(pane);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                  ),
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
        if (!entry.isDir && _isMedia(entry.name))
          AntdActionMenuItem(
            key: 'preview',
            label: _t('sftp.preview'),
            icon: Icons.preview_outlined,
          ),
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
          key: 'cut',
          label: _t('sftp.cut'),
          icon: Icons.content_cut,
        ),
        AntdActionMenuItem(
          key: 'copy',
          label: _t('sftp.copy'),
          icon: Icons.content_copy,
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
                          child: DropTarget(
                            onDragEntered: (_) =>
                                setState(() => pane.dragging = true),
                            onDragExited: (_) =>
                                setState(() => pane.dragging = false),
                            onDragDone: (details) {
                              setState(() => pane.dragging = false);
                              _uploadDropped(pane, details.files);
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                AntdFileList(
                                  files: pane.files
                                      .map((file) => AntdFileEntry(
                                            name:
                                                file['name']?.toString() ?? '',
                                            isDir: file['is_dir'] == true,
                                            size:
                                                (file['size'] as num?)?.toInt(),
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
                                  onFileTap: (entry) {
                                    final file =
                                        entry.extra as Map<String, dynamic>;
                                    _isMedia(entry.name)
                                        ? _preview(pane, file)
                                        : _edit(pane, file);
                                  },
                                  actions: (entry) =>
                                      _actions(pane, other, entry),
                                  onAction: (action, entry) {
                                    final file =
                                        entry.extra as Map<String, dynamic>;
                                    switch (action) {
                                      case 'preview':
                                        _preview(pane, file);
                                      case 'download':
                                        _download(pane, file);
                                      case 'edit':
                                        _edit(pane, file);
                                      case 'transfer':
                                        _transferOne(pane, other, file);
                                      case 'cut':
                                        _setClipboard(
                                            pane, [entry.name], 'cut');
                                      case 'copy':
                                        _setClipboard(
                                            pane, [entry.name], 'copy');
                                      case 'rename':
                                        _rename(pane, file);
                                      case 'delete':
                                        _delete(pane, file);
                                    }
                                  },
                                ),
                                if (pane.dragging)
                                  IgnorePointer(
                                    child: ColoredBox(
                                      color: AntdTokens.primary.withAlpha(28),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AntdTokens.containerColor(
                                                context),
                                            border: Border.all(
                                              color: AntdTokens.primary,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.cloud_upload_outlined,
                                                color: AntdTokens.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(_t('sftp.dropToUpload')),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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

  Widget _editorPanel(Size bounds) {
    final tab = _activeEditor;
    final width = _editorMaximized
        ? bounds.width
        : (bounds.width - 24).clamp(0, 800).toDouble();
    final height = _editorMinimized
        ? 34.0
        : _editorMaximized
            ? bounds.height
            : (bounds.height - 24).clamp(120, 540).toDouble();
    final panel = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AntdTokens.containerColor(context),
        border: Border.all(color: AntdTokens.borderColor(context)),
        borderRadius:
            BorderRadius.circular(_editorMaximized ? 0 : AntdTokens.radiusLG),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 33,
            child: Row(
              children: [
                Expanded(
                  child: AntdTabs(
                    editor: true,
                    height: 32,
                    activeKey: _activeEditorKey,
                    items: _editorTabs
                        .map((item) => AntdTabsItem(
                              key: item.key,
                              label:
                                  Text('${item.dirty ? '● ' : ''}${item.name}'),
                              closable: true,
                            ))
                        .toList(),
                    onChange: (key) => setState(() => _activeEditorKey = key),
                    onClose: _closeEditorTab,
                  ),
                ),
                if (tab != null) ...[
                  _editorAction(
                    tooltip: _t('sftp.searchReplace'),
                    icon: Icons.find_replace,
                    onPressed: () => _findReplace(tab),
                  ),
                  _editorAction(
                    tooltip: _t('sftp.refreshFile'),
                    icon: Icons.refresh,
                    onPressed:
                        tab.loading ? null : () => _refreshEditorTab(tab),
                  ),
                  if (tab.dirty)
                    AntdButton(
                      type: AntdButtonType.primary,
                      size: AntdSize.small,
                      loading: tab.saving,
                      onPressed: tab.saving ? null : () => _saveEditorTab(tab),
                      child: Text(_t('common.save')),
                    ),
                ],
                _editorAction(
                  tooltip: _t('sftp.editorMinimize'),
                  icon: _editorMinimized ? Icons.expand_more : Icons.remove,
                  onPressed: () =>
                      setState(() => _editorMinimized = !_editorMinimized),
                ),
                _editorAction(
                  tooltip: _t('sftp.editorMaximize'),
                  icon: _editorMaximized
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  onPressed: _editorMinimized
                      ? null
                      : () =>
                          setState(() => _editorMaximized = !_editorMaximized),
                ),
                _editorAction(
                  tooltip: _t('sftp.editorClose'),
                  icon: Icons.close,
                  onPressed: _closeAllEditors,
                ),
              ],
            ),
          ),
          if (!_editorMinimized && tab != null) ...[
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: AntdInput(
                        controller: tab.controller,
                        expands: true,
                        keyboardType: TextInputType.multiline,
                        textStyle: const TextStyle(
                          fontFamily: 'TermiScope Mono',
                          fontSize: 13,
                          letterSpacing: 0,
                        ),
                        onChanged: (value) {
                          final dirty = value != tab.savedContent;
                          if (dirty != tab.dirty) {
                            setState(() => tab.dirty = dirty);
                          }
                        },
                      ),
                    ),
                  ),
                  if (tab.loading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x44FFFFFF),
                        child: Center(child: AntdSpin()),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AntdTokens.borderSecondaryColor(context),
                  ),
                ),
              ),
              child: Text(
                tab.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AntdTokens.fontSizeSM,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Positioned(
      right: _editorMaximized ? 0 : 12,
      bottom: _editorMaximized ? 0 : 12,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            final active = _activeEditor;
            if (active != null) _saveEditorTab(active);
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            final active = _activeEditor;
            if (active != null) _saveEditorTab(active);
          },
        },
        child: Focus(autofocus: true, child: panel),
      ),
    );
  }

  Widget _editorAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: AntdButton(
        type: AntdButtonType.text,
        size: AntdSize.small,
        icon: icon,
        onPressed: onPressed,
      ),
    );
  }

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
      body: LayoutBuilder(
        builder: (context, bodyConstraints) => Stack(
          children: [
            Positioned.fill(
              child: Padding(
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
                        final panelHeight = constraints.maxHeight
                            .clamp(480.0, 560.0)
                            .toDouble();
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
                          tasks: _tasks.reversed
                              .take(5)
                              .toList()
                              .reversed
                              .toList(),
                          expanded: true,
                          title: _t('sftp.transferQueue'),
                          cancelText: _t('common.cancel'),
                          retryText: _t('sftp.retry'),
                          clearText: _t('sftp.clearCompleted'),
                          onCancel: _cancelTask,
                          onRetry: _retryTask,
                          onClear: _clearFinishedTasks,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_editorTabs.isNotEmpty) _editorPanel(bodyConstraints.biggest),
          ],
        ),
      ),
    );
  }
}
