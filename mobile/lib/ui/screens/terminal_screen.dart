import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../../data/services/api_service.dart';
import '../../data/services/terminal_service.dart';
import '../../data/services/command_service.dart';
import '../../data/models/command_template.dart';
import '../widgets/sftp_browser_widget.dart';

class TerminalScreen extends StatefulWidget {
  final int hostId;
  final String title;

  const TerminalScreen({super.key, required this.hostId, required this.title});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  late final TerminalService _service;
  late final CommandService _commandService;
  final TerminalController _terminalController = TerminalController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription? _outputSubscription;
  StreamSubscription? _statusSubscription;
  String _status = 'Initializing...';
  bool _isConnected = false;
  bool _isDisposed = false;

  // 命令模板
  List<CommandTemplate> _commandTemplates = [];
  final GlobalKey _commandButtonKey = GlobalKey();

  // 字体设置
  double _fontSize = 14.0;

  // SFTP分屏相关
  bool _showSftp = false;
  double _splitRatio = 0.5; // 分屏比例（0.3-0.7）

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);

    // Inject ApiService
    final apiService = Provider.of<ApiService>(context, listen: false);
    _service = TerminalService(apiService);
    _commandService = CommandService(apiService);

    // 加载设置
    _loadSettings();

    // 加载命令模板
    _loadCommandTemplates();

    // Listen to output
    _outputSubscription = _service.output.listen((data) {
      _terminal.write(data);
    });

    // Listen to status
    _statusSubscription = _service.connectionStatus.listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status == 'Session Started') {
          _isConnected = true;
        } else if (status == 'Disconnected' || status.startsWith('Error')) {
          _isConnected = false;
        }
      });
    });

    // Handle Input
    _terminal.onOutput = (input) {
      _service.sendInput(input);
    };

    // Handle Resize
    _terminal.onResize = (w, h, cols, rows) {
      _service.resize(cols, rows);
    };

    // Connect
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.connect(widget.hostId, 80, 24);
      // Removed manual requestFocus as autofocus: true handles it better
    });
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fontSize = prefs.getDouble('terminal_font_size');
      if (fontSize != null) {
        if (mounted) {
          setState(() {
            _fontSize = fontSize.toDouble();
            // 加载分屏比例
            _splitRatio = prefs.getDouble('terminal_split_ratio') ?? 0.5;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  Future<void> _loadCommandTemplates() async {
    try {
      final templates = await _commandService.getTemplates();
      if (mounted) {
        setState(() => _commandTemplates = templates);
      }
    } catch (e) {
      if (!_isDisposed) {
        debugPrint('Failed to load command templates: $e');
      }
    }
  }

  // 保存分屏状态
  Future<void> _saveSplitState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('terminal_split_ratio', _splitRatio);
    } catch (e) {
      debugPrint('Failed to save split state: $e');
    }
  }

  @override
  void deactivate() {
    // 强制先隐藏键盘，并清除焦点连接，防止 PlatformException
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusScope.of(context).unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _outputSubscription?.cancel();
    _statusSubscription?.cancel();
    _service.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 终端/分屏区域
        Expanded(
          child: _showSftp
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    // 检测屏幕方向：高度>宽度=竖屏
                    final isPortrait =
                        constraints.maxHeight > constraints.maxWidth;

                    if (isPortrait) {
                      // ===== 竖屏：上下布局 =====
                      return Column(
                        children: [
                          // 上方：SFTP浏览器
                          Expanded(
                            flex: (_splitRatio * 100).round(),
                            child: SftpBrowserWidget(hostId: widget.hostId),
                          ),

                          // 分隔条（横向）
                          GestureDetector(
                            onVerticalDragUpdate: (details) {
                              setState(() {
                                final newRatio =
                                    _splitRatio +
                                    (details.delta.dy / constraints.maxHeight);
                                _splitRatio = newRatio.clamp(0.3, 0.7);
                              });
                            },
                            onVerticalDragEnd: (_) => _saveSplitState(),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeRow,
                              child: Container(
                                height: 4,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade400,
                                child: Center(
                                  child: Container(
                                    width: 40,
                                    height: 2,
                                    color: isDark
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 下方：终端
                          Expanded(
                            flex: ((1 - _splitRatio) * 100).round(),
                            child: GestureDetector(
                              onTap: () {
                                if (!_focusNode.hasFocus) {
                                  _focusNode.requestFocus();
                                }
                              },
                              child: TerminalView(
                                _terminal,
                                controller: _terminalController,
                                autofocus: true,
                                focusNode: _focusNode,
                                backgroundOpacity: 1,
                                keyboardType: TextInputType.visiblePassword,
                                textStyle: TerminalStyle(fontSize: _fontSize),
                              ),
                            ),
                          ),
                        ],
                      );
                    } else {
                      // ===== 横屏：左右布局 =====
                      return Row(
                        children: [
                          // 左侧：终端
                          Expanded(
                            flex: (_splitRatio * 100).round(),
                            child: GestureDetector(
                              onTap: () {
                                if (!_focusNode.hasFocus) {
                                  _focusNode.requestFocus();
                                }
                              },
                              child: TerminalView(
                                _terminal,
                                controller: _terminalController,
                                autofocus: true,
                                focusNode: _focusNode,
                                backgroundOpacity: 1,
                                keyboardType: TextInputType.visiblePassword,
                                textStyle: TerminalStyle(fontSize: _fontSize),
                              ),
                            ),
                          ),

                          // 分隔条（纵向）
                          GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                final newRatio =
                                    _splitRatio +
                                    (details.delta.dx / constraints.maxWidth);
                                _splitRatio = newRatio.clamp(0.3, 0.7);
                              });
                            },
                            onHorizontalDragEnd: (_) => _saveSplitState(),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: Container(
                                width: 4,
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade400,
                                child: Center(
                                  child: Container(
                                    width: 2,
                                    height: 40,
                                    color: isDark
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 右侧：SFTP浏览器
                          Expanded(
                            flex: ((1 - _splitRatio) * 100).round(),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              child: SftpBrowserWidget(hostId: widget.hostId),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                )
              : GestureDetector(
                  onTap: () {
                    if (!_focusNode.hasFocus) {
                      _focusNode.requestFocus();
                    }
                  },
                  child: TerminalView(
                    _terminal,
                    controller: _terminalController,
                    autofocus: true,
                    focusNode: _focusNode,
                    backgroundOpacity: 1,
                    keyboardType: TextInputType.visiblePassword,
                    textStyle: TerminalStyle(fontSize: _fontSize),
                  ),
                ),
        ),
        // 底部工具栏 - 参照Web版
        _buildBottomToolbar(isDark),
      ],
    );
  }

  /// 底部工具栏（移动端）
  Widget _buildBottomToolbar(bool isDark) {
    return Material(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          ),
        ),
        child: Row(
          children: [
            // 左侧操作按钮（可滚动，防止溢出）
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 断开连接按钮（红色）
                    _bottomBtn(
                      Icons.link_off,
                      '断开',
                      _isConnected ? Colors.red : null,
                      () {
                        _service.dispose();
                        setState(() => _isConnected = false);
                      },
                    ),
                    _verticalDivider(isDark),
                    // 字体设置
                    _bottomBtn(
                      Icons.text_fields,
                      '字体',
                      null,
                      _showFontSettings,
                    ),
                    _verticalDivider(isDark),
                    // SFTP浏览器
                    _bottomBtn(
                      Icons.folder_open,
                      'SFTP',
                      null,
                      _isConnected ? _openSftpBrowser : null,
                    ),
                    _verticalDivider(isDark),
                    // 命令模板（添加key用于定位菜单）
                    Container(
                      key: _commandButtonKey,
                      child: _bottomBtn(
                        Icons.code,
                        '命令',
                        null,
                        _showCommandMenu,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 右侧状态
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _isConnected
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _isConnected ? 'Connected' : _status,
                style: TextStyle(
                  fontSize: 10,
                  color: _isConnected ? Colors.green : Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verticalDivider(bool isDark) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
    );
  }

  Widget _bottomBtn(
    IconData icon,
    String label,
    Color? color,
    VoidCallback? onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final btnColor =
        color ?? (isDark ? Colors.grey.shade400 : Colors.grey.shade700);
    final isDisabled = onTap == null;

    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: btnColor),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: btnColor)),
            ],
          ),
        ),
      ),
    );
  }

  // 字体设置对话框
  void _showFontSettings() {
    double tempFontSize = _fontSize;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('字体设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('字体大小:'),
                  const SizedBox(width: 8),
                  Text('${tempFontSize.toInt()}'),
                ],
              ),
              Slider(
                value: tempFontSize,
                min: 10,
                max: 24,
                divisions: 14,
                label: '${tempFontSize.toInt()}',
                onChanged: (val) {
                  setDialogState(() => tempFontSize = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  _fontSize = tempFontSize;
                });

                // 保存设置
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('terminal_font_size', tempFontSize);
                } catch (e) {
                  debugPrint('Failed to save font size: $e');
                }

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('字体大小已设置为 ${tempFontSize.toInt()}')),
                  );
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // SFTP浏览器
  void _openSftpBrowser() {
    // TODO: 实现SFTP浏览器，需要创建SftpBrowserScreen
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('SFTP浏览器功能开发中...')));
  }

  // 命令模板菜单
  void _showCommandMenu() {
    if (_commandTemplates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无命令模板')));
      return;
    }

    final RenderBox? button =
        _commandButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size size = button.size;

    showMenu<CommandTemplate>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + size.width,
        offset.dy + size.height,
      ),
      items: _commandTemplates.map((template) {
        return PopupMenuItem<CommandTemplate>(
          value: template,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                template.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (template.description.isNotEmpty)
                Text(
                  template.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null && _isConnected) {
        // 发送命令到终端
        _service.sendInput('${selected.command}\n');
      }
    });
  }
}
