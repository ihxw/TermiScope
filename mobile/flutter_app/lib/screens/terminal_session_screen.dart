import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

import '../app/antd_tokens.dart';
import '../app/terminal_theme.dart';
import '../providers/app_state.dart';
import '../services/local_terminal_service.dart';
import '../services/terminal_connection.dart';
import '../services/terminal_service.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import '../widgets/web_terminal/web_terminal_view.dart';
import 'file_transfer_screen.dart';
import 'command_templates_screen.dart';

class TerminalSessionView extends StatefulWidget {
  final int hostId;
  final String hostLabel;
  final bool record;
  final bool active;
  final bool localNetwork;

  const TerminalSessionView({
    super.key,
    required this.hostId,
    required this.hostLabel,
    this.record = false,
    this.active = true,
    this.localNetwork = false,
  });

  @override
  State<TerminalSessionView> createState() => _TerminalSessionViewState();
}

class _TerminalAppearance {
  const _TerminalAppearance({
    required this.fontSize,
    required this.fontFamily,
    required this.themeKey,
    required this.brightness,
  });

  final double fontSize;
  final String fontFamily;
  final String themeKey;
  final Brightness brightness;

  @override
  bool operator ==(Object other) {
    return other is _TerminalAppearance &&
        other.fontSize == fontSize &&
        other.fontFamily == fontFamily &&
        other.themeKey == themeKey &&
        other.brightness == brightness;
  }

  @override
  int get hashCode => Object.hash(
        fontSize,
        fontFamily,
        themeKey,
        brightness,
      );
}

class _TerminalSessionViewState extends State<TerminalSessionView> {
  late final Terminal terminal;
  late final TerminalController terminalController;
  late final WebTerminalController _webTerminalController;
  late final ValueNotifier<String> _connectionStatusNotifier;
  late final ValueNotifier<String> _terminalSizeNotifier;
  final FocusNode _focusNode = FocusNode();
  TerminalConnection? _terminalService;
  TerminalStyle? _cachedTerminalStyle;
  double? _cachedFontSize;
  String? _cachedFontFamily;
  final ListQueue<String> _pendingTerminalOutput = ListQueue();
  int _pendingTerminalOutputLength = 0;
  Timer? _terminalOutputFlushTimer;
  String _connectionStatus = 'Connecting...';
  String _terminalSize = '80x24';
  bool _selectionMode = false;
  bool _manualDisconnected = false;
  bool _disposed = false;
  bool _sftpVisible = false;
  bool _commandSheetOpen = false;
  bool _fingerprintPromptOpen = false;
  double _sftpSplitRatio = 0.5;
  String? _terminalCwd;
  final StringBuffer _commandBuffer = StringBuffer();
  Timer? _reconnectTimer;
  String? _accountPassword;

  static const int _inactiveOutputLimit = 512 * 1024;
  static const int _inactiveOutputRetain = 384 * 1024;

  static const List<AntdSelectOption<String>> _fontOptions = [
    AntdSelectOption(value: 'TermiScope Mono', label: 'TermiScope Mono'),
    AntdSelectOption(value: 'Courier New', label: 'Courier New'),
    AntdSelectOption(value: 'Consolas', label: 'Consolas'),
    AntdSelectOption(value: 'Menlo', label: 'Menlo / Monaco'),
    AntdSelectOption(value: 'monospace', label: 'System Monospace'),
  ];

  static const List<String> _fontFallback = [
    'TermiScope Mono',
    'Menlo',
    'Monaco',
    'Consolas',
    'Courier New',
    'Noto Sans Mono CJK SC',
    'monospace',
  ];

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 1000);
    terminalController = TerminalController();
    _webTerminalController = WebTerminalController();
    _connectionStatusNotifier = ValueNotifier(_connectionStatus);
    _terminalSizeNotifier = ValueNotifier(_terminalSize);

    terminal.onOutput = _handleTerminalInput;
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      if (_disposed) return;
      final nextSize = '${width}x$height';
      if (nextSize == _terminalSize) return;
      _terminalSize = nextSize;
      _terminalSizeNotifier.value = _terminalSize;
      _terminalService?.resize(width, height);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && mounted) _connect();
    });
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _restoreSplitRatio();
  }

  @override
  void didUpdateWidget(covariant TerminalSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _scheduleTerminalFlush();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && mounted) _focusNode.requestFocus();
      });
    }
  }

  Future<void> _restoreSplitRatio() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble('terminal_split_ratio');
    if (saved != null && mounted) {
      setState(() => _sftpSplitRatio = saved.clamp(0.3, 0.7));
    }
  }

  Future<void> _connect() async {
    if (_disposed || !mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _manualDisconnected = false;
    final appState = context.read<AppState>();
    final oldService = _terminalService;
    _terminalService = null;
    oldService?.onStatusChanged = null;
    oldService?.onData = null;
    oldService?.dispose();
    final service = await _createTerminalConnection(appState);
    if (_disposed || !mounted || service == null) return;
    service.onData = (text) {
      if (_disposed || !mounted || _terminalService != service) return;
      _enqueueTerminalOutput(text);
    };
    service.onStatusChanged = (status) {
      if (_disposed || !mounted || _terminalService != service) return;
      _connectionStatus = status;
      _connectionStatusNotifier.value = status;
      if (status == 'Disconnected' &&
          !_manualDisconnected &&
          !_fingerprintPromptOpen) {
        _scheduleReconnect();
      }
    };
    service.onFingerprintMismatch = (fingerprint) {
      if (_disposed || !mounted || _terminalService != service) return;
      _handleFingerprintMismatch(fingerprint);
    };
    _terminalService = service;

    final success = await service.connect();
    if (_disposed || !mounted || _terminalService != service) return;
    if (!success) {
      if (!widget.localNetwork) {
        _enqueueTerminalOutput(
          '\r\n\x1b[31mFailed to get WS ticket or connect.\x1b[0m\r\n',
        );
      }
    }
    if (!_disposed && mounted) _focusNode.requestFocus();
  }

  Future<TerminalConnection?> _createTerminalConnection(
    AppState appState,
  ) async {
    if (!widget.localNetwork) {
      return TerminalService(
        appState,
        widget.hostId.toString(),
        record: widget.record,
      );
    }
    if (kIsWeb) {
      _connectionStatus = 'Error';
      _connectionStatusNotifier.value = _connectionStatus;
      _enqueueTerminalOutput(
        '\r\n\x1b[31m本地网络直连不支持 Web，请使用桌面或移动应用。\x1b[0m\r\n',
      );
      return null;
    }

    final matchingHosts =
        appState.hosts.where((item) => item.id == widget.hostId);
    if (matchingHosts.isEmpty) {
      _connectionStatus = 'Error';
      _connectionStatusNotifier.value = _connectionStatus;
      _enqueueTerminalOutput('\r\n\x1b[31m未找到主机配置。\x1b[0m\r\n');
      return null;
    }
    final host = matchingHosts.first;

    var password = _accountPassword ?? appState.apiService.decryptedPassword;
    password ??= await _promptForAccountPassword(appState);
    if (password == null || password.isEmpty || !mounted) {
      _connectionStatus = 'Disconnected';
      _connectionStatusNotifier.value = _connectionStatus;
      return null;
    }

    Map<String, dynamic> credentials;
    try {
      credentials =
          await appState.revealHostCredentials(widget.hostId, password);
    } catch (_) {
      password = await _promptForAccountPassword(appState, invalid: true);
      if (password == null || password.isEmpty || !mounted) {
        _connectionStatus = 'Disconnected';
        _connectionStatusNotifier.value = _connectionStatus;
        return null;
      }
      try {
        credentials =
            await appState.revealHostCredentials(widget.hostId, password);
      } catch (error) {
        _connectionStatus = 'Error';
        _connectionStatusNotifier.value = _connectionStatus;
        _enqueueTerminalOutput(
          '\r\n\x1b[31m读取主机凭据失败：${error.toString().replaceAll('Exception: ', '')}\x1b[0m\r\n',
        );
        return null;
      }
    }
    _accountPassword = password;
    if (widget.record) {
      _enqueueTerminalOutput(
        '\r\n\x1b[33m本地网络直连不会经过服务器，因此不支持服务端会话录制。\x1b[0m\r\n',
      );
    }
    return LocalTerminalService(
      host: host,
      password: credentials['password']?.toString() ?? '',
      privateKey: credentials['private_key']?.toString() ?? '',
    );
  }

  Future<String?> _promptForAccountPassword(
    AppState appState, {
    bool invalid = false,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AntdModal(
        title: Text(appState.locale == 'zh' ? '验证当前账户' : 'Verify account'),
        width: 420,
        okText: Translation.getText(appState.locale, 'common.confirm'),
        cancelText: Translation.getText(appState.locale, 'common.cancel'),
        onOk: () => Navigator.of(dialogContext).pop(controller.text),
        onCancel: () => Navigator.of(dialogContext).pop(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              invalid
                  ? (appState.locale == 'zh'
                      ? '密码无效，请输入当前 TermiScope 账户密码。'
                      : 'The password is invalid. Enter your current TermiScope account password.')
                  : (appState.locale == 'zh'
                      ? '本地直连需要读取该主机的 SSH 凭据，请输入当前 TermiScope 账户密码。'
                      : 'Direct SSH needs the saved host credentials. Enter your current TermiScope account password.'),
            ),
            const SizedBox(height: 12),
            AntdPasswordInput(
              controller: controller,
              prefixIcon: Icons.lock_outline,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  void _disconnect() {
    _manualDisconnected = true;
    _reconnectTimer?.cancel();
    final service = _terminalService;
    _terminalService = null;
    service?.onData = null;
    service?.onStatusChanged = null;
    service?.dispose();
    _connectionStatus = 'Disconnected';
    _connectionStatusNotifier.value = _connectionStatus;
    _enqueueTerminalOutput('\r\n\x1b[33mDisconnected\x1b[0m\r\n');
  }

  void _reconnect() {
    if (_disposed || !mounted) return;
    _reconnectTimer?.cancel();
    _enqueueTerminalOutput('\r\n\x1b[36mReconnecting...\x1b[0m\r\n');
    _connect();
  }

  Future<void> _handleFingerprintMismatch(String fingerprint) async {
    _fingerprintPromptOpen = true;
    _reconnectTimer?.cancel();
    final state = context.read<AppState>();
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AntdModal(
        title: Text(Translation.getText(
          state.locale,
          'terminal.fingerprintMismatchTitle',
        )),
        width: 520,
        okText: Translation.getText(
          state.locale,
          'terminal.fingerprintAccept',
        ),
        cancelText: Translation.getText(state.locale, 'common.cancel'),
        onOk: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translation.getText(
              state.locale,
              'terminal.fingerprintMismatchWarning1',
            )),
            const SizedBox(height: 8),
            Text(Translation.getText(
              state.locale,
              'terminal.fingerprintMismatchWarning2',
            )),
            const SizedBox(height: 12),
            SelectableText(
              '${Translation.getText(state.locale, 'terminal.fingerprintNew')}: $fingerprint',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              Translation.getText(
                state.locale,
                'terminal.fingerprintAcceptPrompt',
              ),
              style: const TextStyle(color: AntdTokens.warning),
            ),
          ],
        ),
      ),
    );
    _fingerprintPromptOpen = false;
    if (!mounted || accepted == null) return;
    if (!accepted) {
      _enqueueTerminalOutput(
        '\r\n\x1b[31m${Translation.getText(state.locale, 'terminal.fingerprintRejected')}\x1b[0m\r\n',
      );
      return;
    }
    try {
      await state.apiService.put(
        '/api/ssh-hosts/${widget.hostId}/fingerprint',
        {'fingerprint': fingerprint},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(Translation.getText(
          state.locale,
          'terminal.fingerprintUpdated',
        )),
      ));
      _reconnect();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AntdTokens.error,
        content: Text(
          '${Translation.getText(state.locale, 'terminal.fingerprintUpdateFailed')}: $error',
        ),
      ));
    }
  }

  void _enqueueTerminalOutput(String text) {
    if (text.isEmpty || _disposed) return;
    _pendingTerminalOutput.addLast(text);
    _pendingTerminalOutputLength += text.length;
    if (!widget.active) {
      if (_pendingTerminalOutputLength > _inactiveOutputLimit) {
        _discardOldTerminalOutput(
          _pendingTerminalOutputLength - _inactiveOutputRetain,
        );
      }
      return;
    }
    _scheduleTerminalFlush();
  }

  void _discardOldTerminalOutput(int count) {
    var remaining = count;
    while (remaining > 0 && _pendingTerminalOutput.isNotEmpty) {
      final first = _pendingTerminalOutput.removeFirst();
      if (first.length <= remaining) {
        remaining -= first.length;
        _pendingTerminalOutputLength -= first.length;
      } else {
        _pendingTerminalOutput.addFirst(first.substring(remaining));
        _pendingTerminalOutputLength -= remaining;
        remaining = 0;
      }
    }
  }

  void _scheduleTerminalFlush() {
    if (_terminalOutputFlushTimer != null || !widget.active) return;
    _terminalOutputFlushTimer = Timer(
      const Duration(milliseconds: kIsWeb ? 12 : 8),
      _flushPendingOutput,
    );
  }

  void _flushPendingOutput() {
    _terminalOutputFlushTimer = null;
    if (_disposed || !widget.active || _pendingTerminalOutput.isEmpty) return;

    // Process bounded chunks so large bursts cannot block the UI isolate.
    const maxChunkSize = kIsWeb ? 65536 : 16384;
    final output = StringBuffer();
    var remaining = maxChunkSize;
    while (remaining > 0 && _pendingTerminalOutput.isNotEmpty) {
      final first = _pendingTerminalOutput.removeFirst();
      if (first.length <= remaining) {
        output.write(first);
        remaining -= first.length;
        _pendingTerminalOutputLength -= first.length;
      } else {
        output.write(first.substring(0, remaining));
        _pendingTerminalOutput.addFirst(first.substring(remaining));
        _pendingTerminalOutputLength -= remaining;
        remaining = 0;
      }
    }
    _writeTerminalOutput(output.toString());
    if (_pendingTerminalOutput.isNotEmpty) _scheduleTerminalFlush();
  }

  void _writeTerminalOutput(String data) {
    if (kIsWeb) {
      _webTerminalController.write(data);
    } else {
      terminal.write(data);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _terminalOutputFlushTimer?.cancel();
    _terminalOutputFlushTimer = null;
    _accountPassword = null;
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    final service = _terminalService;
    _terminalService = null;
    service?.onData = null;
    service?.onStatusChanged = null;
    service?.dispose();
    terminal.onOutput = null;
    terminal.onResize = null;
    _webTerminalController.dispose();
    _connectionStatusNotifier.dispose();
    _terminalSizeNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showLongPressMenu() {
    final hasSelection = terminalController.selection != null;
    showModalBottomSheet(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!hasSelection)
              ListTile(
                leading: const Icon(Icons.select_all),
                title: const Text('选择可见内容并复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  _selectVisibleAndCopy();
                },
              ),
            if (hasSelection)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copySelection();
                },
              ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('粘贴'),
              onTap: () {
                Navigator.pop(ctx);
                _pasteFromClipboard();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selectVisibleAndCopy() {
    if (kIsWeb) {
      _webTerminalController.selectAll();
      Future.delayed(const Duration(milliseconds: 50), _copySelection);
      return;
    }
    final lines = terminal.buffer.lines;
    final height = terminal.viewHeight;
    if (lines.length == 0 || height == 0) return;
    final lastIdx = height - 1 < lines.length ? height - 1 : lines.length - 1;
    terminalController.setSelection(
      CellAnchor(0, owner: lines[0]),
      CellAnchor(0, owner: lines[lastIdx]),
    );
    Future.delayed(const Duration(milliseconds: 100), _copySelection);
  }

  void _copySelection() {
    final text = kIsWeb
        ? _webTerminalController.getSelection()
        : terminalController.selection == null
            ? ''
            : terminal.buffer.getText(terminalController.selection!);
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    if (kIsWeb) {
      _webTerminalController.clearSelection();
    } else {
      terminalController.clearSelection();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    _handleTerminalInput(data.text!);
    _focusNode.requestFocus();
  }

  void _send(String value) {
    _handleTerminalInput(value);
    _focusNode.requestFocus();
  }

  void _handleTerminalInput(String data) {
    _trackTerminalDirectory(data);
    _terminalService?.write(data);
  }

  void _trackTerminalDirectory(String data) {
    for (final code in data.codeUnits) {
      if (code == 13 || code == 10) {
        final command = _commandBuffer.toString().trim();
        _commandBuffer.clear();
        final match = RegExp(r'^cd(?:\s+(.+))?$').firstMatch(command);
        if (match != null) {
          final target = (match.group(1) ?? '')
              .trim()
              .replaceAll(RegExp(r'''^['"]|['"]$'''), '');
          if (target.startsWith('/')) {
            _terminalCwd = _normalizePath(target);
          } else if (target == '..' && _terminalCwd != null) {
            final parts = _terminalCwd!.split('/')
              ..removeWhere((part) => part.isEmpty);
            if (parts.isNotEmpty) parts.removeLast();
            _terminalCwd = '/${parts.join('/')}';
          } else if (target.isNotEmpty &&
              target != '~' &&
              _terminalCwd != null) {
            _terminalCwd = _normalizePath('${_terminalCwd!}/$target');
          }
        }
      } else if (code == 8 || code == 127) {
        final current = _commandBuffer.toString();
        if (current.isNotEmpty) {
          _commandBuffer
            ..clear()
            ..write(current.substring(0, current.length - 1));
        }
      } else if (code >= 32 && code != 127) {
        _commandBuffer.writeCharCode(code);
      }
    }
  }

  String _normalizePath(String input) {
    final parts = <String>[];
    for (final part in input.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnected || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      if (!_disposed && mounted && !_manualDisconnected) _reconnect();
    });
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent || _disposed || !widget.active) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed && event.logicalKey == LogicalKeyboardKey.keyK) {
      if (_connectionStatus == 'Connected') _showCommandTemplates();
      return true;
    }
    if (!_commandSheetOpen ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final index = int.tryParse(event.logicalKey.keyLabel);
    final templates = context.read<AppState>().commandTemplates;
    if (index == null || index < 1 || index > 9 || index > templates.length) {
      return false;
    }
    _runCommandTemplate(templates[index - 1]);
    Navigator.of(context).maybePop();
    return true;
  }

  void _runCommandTemplate(dynamic template) {
    _send('${template.command}${template.autoEnter ? '\r' : ''}');
  }

  void _sendCtrl(String key) {
    if (key.isEmpty) return;
    final code = key.toLowerCase().codeUnitAt(0) - 96;
    if (code < 1 || code > 26) return;
    _send(String.fromCharCode(code));
  }

  void _toggleSelectionMode() {
    setState(() => _selectionMode = !_selectionMode);
    terminalController.setSelectionMode(
      _selectionMode ? SelectionMode.block : SelectionMode.line,
    );
    terminalController.setSuspendPointerInput(_selectionMode);
  }

  Future<void> _showCommandTemplates() async {
    if (_commandSheetOpen) return;
    final appState = context.read<AppState>();
    await appState.fetchCommandTemplates();
    if (!mounted) return;
    _commandSheetOpen = true;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.flash_on_outlined,
                        color: AntdTokens.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '命令模板',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AntdTokens.fontSizeLG,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: AntdTokens.borderSecondaryColor(context),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: appState.commandTemplates.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: AntdTokens.borderSecondaryColor(context),
                  ),
                  itemBuilder: (context, index) {
                    final item = appState.commandTemplates[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.name),
                      subtitle: Text(
                        item.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AntdTag(
                            preset: item.autoEnter
                                ? AntdTagPreset.success
                                : AntdTagPreset.defaultStyle,
                            label: item.autoEnter
                                ? (appState.locale == 'zh' ? '执行' : 'Run')
                                : (appState.locale == 'zh' ? '插入' : 'Insert'),
                          ),
                          if (index < 9) ...[
                            const SizedBox(width: 4),
                            AntdTag(
                              color: AntdTokens.primary,
                              label: '${index + 1}',
                            ),
                          ],
                        ],
                      ),
                      onTap: () {
                        _runCommandTemplate(item);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
              Divider(
                height: 1,
                color: AntdTokens.borderSecondaryColor(context),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_outlined),
                title: Text(Translation.getText(
                  appState.locale,
                  'terminal.manageTemplates',
                )),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommandTemplatesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    _commandSheetOpen = false;
  }

  Future<void> _showDesktopContextMenu(TapDownDetails details) async {
    final position = details.globalPosition;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy, size: 18),
            title: Text('Copy'),
          ),
        ),
        PopupMenuItem(
          value: 'paste',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.content_paste, size: 18),
            title: Text('Paste'),
          ),
        ),
      ],
    );
    if (action == 'copy') _copySelection();
    if (action == 'paste') _pasteFromClipboard();
  }

  void _showThemeMenu(AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AntdTokens.containerColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: TerminalThemeCatalog.options.values.map((option) {
            final selected = option.key == state.terminalTheme;
            return ListTile(
              dense: true,
              leading: Icon(
                selected ? Icons.check : Icons.palette_outlined,
                color: selected ? AntdTokens.primary : null,
              ),
              title: Text(option.name),
              onTap: () {
                state.updateTerminalTheme(option.key);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFontSettings(AppState state) {
    double size = state.terminalFontSize;
    String family = state.terminalFontFamily;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AntdModal(
          title: const Text('字体设置'),
          width: 360,
          showFooter: true,
          okText: '完成',
          cancelText: '取消',
          onOk: () {
            state.updateTerminalFontFamily(family);
            state.updateTerminalFontSize(size);
            Navigator.pop(ctx);
          },
          onCancel: () => Navigator.pop(ctx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '字体',
                style: TextStyle(
                  fontSize: AntdTokens.fontSizeSM,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
              const SizedBox(height: 4),
              AntdSelect<String>(
                value: family,
                options: _fontOptions,
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => family = value);
                },
              ),
              const SizedBox(height: 16),
              Text(
                '字号 (${size.round()}px)',
                style: TextStyle(
                  fontSize: AntdTokens.fontSizeSM,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
              Slider(
                value: size,
                min: 10,
                max: 32,
                divisions: 22,
                label: size.round().toString(),
                onChanged: (value) {
                  setDialogState(() => size = value);
                },
                onChangeEnd: (value) {
                  setDialogState(() => size = value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, _TerminalAppearance>(
      selector: (_, state) => _TerminalAppearance(
        fontSize: state.terminalFontSize,
        fontFamily: state.terminalFontFamily,
        themeKey: state.terminalTheme,
        brightness: Theme.of(context).brightness,
      ),
      builder: (context, appearance, child) {
        final terminalTheme = TerminalThemeCatalog.resolve(
          appearance.themeKey,
          appearance.brightness,
        );
        final terminalBg = terminalTheme.background;
        final style = _terminalStyleFor(
          appearance.fontSize,
          appearance.fontFamily,
        );
        return Container(
          color: terminalBg,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final terminalView = GestureDetector(
                      onTap: () {
                        if (kIsWeb) {
                          _webTerminalController.focus();
                        } else {
                          _focusNode.requestFocus();
                        }
                      },
                      onLongPress: _showLongPressMenu,
                      onSecondaryTapDown: _showDesktopContextMenu,
                      child: kIsWeb
                          ? WebTerminalView(
                              controller: _webTerminalController,
                              theme: terminalTheme,
                              fontFamily: appearance.fontFamily,
                              fontSize: appearance.fontSize,
                              onData: _handleTerminalInput,
                              onResize: (cols, rows) {
                                final nextSize = '${cols}x$rows';
                                if (nextSize == _terminalSize) return;
                                _terminalSize = nextSize;
                                _terminalSizeNotifier.value = _terminalSize;
                                _terminalService?.resize(cols, rows);
                              },
                            )
                          : TerminalView(
                              key: ValueKey(
                                'terminal-${appearance.fontFamily}-${appearance.fontSize}',
                              ),
                              terminal,
                              controller: terminalController,
                              focusNode: _focusNode,
                              hardwareKeyboardOnly:
                                  _useHardwareKeyboardOnly(context),
                              backgroundOpacity: 1.0,
                              simulateScroll: false,
                              theme: terminalTheme,
                              textStyle: style,
                            ),
                    );
                    if (!_sftpVisible) return terminalView;
                    final sftp = FileTransferScreen(
                      initialHostId: widget.hostId,
                      initialPath: _terminalCwd,
                      singlePane: true,
                      lockInitialHost: true,
                    );
                    if (constraints.maxWidth <= 768) {
                      return AntdSplitPane(
                        direction: Axis.vertical,
                        initialRatio: _sftpSplitRatio,
                        minRatio: 0.3,
                        maxRatio: 0.7,
                        first: terminalView,
                        second: sftp,
                        onRatioChanged: (ratio) => _sftpSplitRatio = ratio,
                        onRatioChangeEnd: _saveSplitRatio,
                      );
                    }
                    return AntdSplitPane(
                      initialRatio: _sftpSplitRatio,
                      minRatio: 0.3,
                      maxRatio: 0.7,
                      first: terminalView,
                      second: sftp,
                      onRatioChanged: (ratio) => _sftpSplitRatio = ratio,
                      onRatioChangeEnd: _saveSplitRatio,
                    );
                  },
                ),
              ),
              if (_isTouchLayout(context)) _buildMobileKeyboard(context),
              _buildStatusBar(context),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveSplitRatio(double ratio) async {
    _sftpSplitRatio = ratio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_split_ratio', ratio);
  }

  TerminalStyle _terminalStyleFor(double fontSize, String fontFamily) {
    if (_cachedTerminalStyle != null &&
        _cachedFontSize == fontSize &&
        _cachedFontFamily == fontFamily) {
      return _cachedTerminalStyle!;
    }
    _cachedFontSize = fontSize;
    _cachedFontFamily = fontFamily;
    _cachedTerminalStyle = TerminalStyle(
      fontSize: fontSize,
      height: 1,
      fontFamily: fontFamily,
      fontFamilyFallback: _fontFallback,
    );
    return _cachedTerminalStyle!;
  }

  bool _isTouchLayout(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width <= 1024 ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  bool _isDesktopPlatform() {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  bool _useHardwareKeyboardOnly(BuildContext context) {
    if (!kIsWeb) return _isDesktopPlatform();
    return MediaQuery.of(context).size.width > 768;
  }

  Widget _buildMobileKeyboard(BuildContext context) {
    final dark = AntdTokens.isDark(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2D2D2D) : const Color(0xFFF0F0F0),
        border: Border(
          top: BorderSide(
            color: dark ? const Color(0xFF404040) : const Color(0xFFD9D9D9),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _keyButton('Ctrl', null, active: false),
          _keyButton('Alt', null, active: false),
          _keyButton('Shift', null, active: false),
          _separator(),
          _keyButton('Esc', '\x1b'),
          _keyButton('Tab', '\t'),
          _separator(),
          _keyButton('↑', '\x1b[A'),
          _keyButton('↓', '\x1b[B'),
          _keyButton('←', '\x1b[D'),
          _keyButton('→', '\x1b[C'),
          _separator(),
          for (final key in [
            'c',
            'd',
            'z',
            'l',
            'a',
            'e',
            'u',
            'r',
            'x',
            'o',
            'w',
            'k',
            'p',
            'n',
          ])
            _keyButton(
              '^${key.toUpperCase()}',
              null,
              onTap: () => _sendCtrl(key),
            ),
          _separator(),
          for (final char in ['|', '&', '~', '/', '-', '_'])
            _keyButton(char, char),
          _separator(),
          _keyButton(
            _selectionMode ? '取消选择' : '选择文字',
            null,
            active: _selectionMode,
            onTap: _toggleSelectionMode,
          ),
          _keyButton('Copy', null, onTap: _copySelection),
          _keyButton('Paste', null, onTap: _pasteFromClipboard),
        ],
      ),
    );
  }

  Widget _keyButton(String label, String? value,
      {bool active = false, VoidCallback? onTap}) {
    final dark = AntdTokens.isDark(context);
    final bg = active
        ? AntdTokens.warning
        : (dark ? const Color(0xFF3A3A3A) : Colors.white);
    final fg = active
        ? Colors.white
        : (dark ? const Color(0xFFE0E0E0) : const Color(0xFF333333));
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap ?? (value == null ? null : () => _send(value)),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: active
                    ? AntdTokens.warning
                    : (dark
                        ? const Color(0xFF555555)
                        : const Color(0xFFD9D9D9)),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _separator() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        color: AntdTokens.isDark(context)
            ? const Color(0xFF4A4A4A)
            : const Color(0xFFD9D9D9),
      );

  Widget _buildStatusBar(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _connectionStatusNotifier,
      builder: (context, status, child) {
        final dark = AntdTokens.isDark(context);
        final connected = status == 'Connected';
        final disconnected = status == 'Disconnected';
        final retryable = disconnected || status == 'Error';
        final statusColor = _statusColor(status);

        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1F1F1F) : const Color(0xFFF0F0F0),
            border: Border(
              top: BorderSide(
                color: dark ? const Color(0xFF303030) : const Color(0xFFD9D9D9),
              ),
            ),
          ),
          child: Row(
            children: [
              if (retryable || _manualDisconnected)
                _statusButton(Icons.refresh, '重连', _reconnect)
              else
                _statusButton(
                  Icons.link_off_outlined,
                  '断开',
                  connected ? _disconnect : null,
                  danger: connected,
                ),
              _statusDivider(),
              _statusButton(
                Icons.palette_outlined,
                '主题',
                () => _showThemeMenu(context.read<AppState>()),
              ),
              _statusDivider(),
              _statusButton(
                Icons.format_size,
                '字体',
                () => _showFontSettings(context.read<AppState>()),
              ),
              _statusDivider(),
              _statusButton(
                Icons.folder_open_outlined,
                'SFTP',
                connected && !widget.localNetwork
                    ? () => setState(() => _sftpVisible = !_sftpVisible)
                    : null,
              ),
              _statusDivider(),
              _statusButton(
                Icons.flash_on_outlined,
                '命令',
                connected ? _showCommandTemplates : null,
              ),
              const Spacer(),
              if (widget.localNetwork) ...[
                const Icon(
                  Icons.lan_outlined,
                  size: 14,
                  color: AntdTokens.primary,
                ),
                const SizedBox(width: 4),
                const Text(
                  'LOCAL',
                  style: TextStyle(
                    color: AntdTokens.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<String>(
                valueListenable: _terminalSizeNotifier,
                builder: (context, size, child) {
                  return Text(
                    size,
                    style: TextStyle(
                      color: dark
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFF666666),
                      fontSize: 11,
                    ),
                  );
                },
              ),
              if (widget.record && !widget.localNetwork) ...[
                _statusDivider(),
                const _RecordingIndicator(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusButton(IconData icon, String label, VoidCallback? onPressed,
      {bool danger = false}) {
    final disabled = onPressed == null;
    final color = disabled
        ? AntdTokens.disabledTextColor(context)
        : (danger ? AntdTokens.error : AntdTokens.textColor(context));
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _statusDivider() => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AntdTokens.isDark(context)
            ? Colors.white.withOpacity(0.18)
            : Colors.black.withOpacity(0.10),
      );

  Color _statusColor(String status) {
    switch (status) {
      case 'Connected':
        return AntdTokens.success;
      case 'Disconnected':
        return AntdTokens.error;
      case 'Error':
        return AntdTokens.error;
      default:
        return AntdTokens.primary;
    }
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fiber_manual_record, color: AntdTokens.error, size: 10),
        SizedBox(width: 4),
        Text(
          'RECORDING',
          style: TextStyle(
            color: AntdTokens.error,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
