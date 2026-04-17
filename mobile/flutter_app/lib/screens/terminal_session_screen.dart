import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/app_state.dart';
import '../services/terminal_service.dart';

class TerminalSessionView extends StatefulWidget {
  final int hostId;

  const TerminalSessionView({
    super.key,
    required this.hostId,
  });

  @override
  State<TerminalSessionView> createState() => _TerminalSessionViewState();
}

class _TerminalSessionViewState extends State<TerminalSessionView> {
  late final Terminal terminal;
  late final TerminalController terminalController;
  final FocusNode _focusNode = FocusNode();
  TerminalService? _terminalService;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(
      maxLines: 10000,
    );
    terminalController = TerminalController();

    // Setup input routing: from terminal view -> websocket
    terminal.onOutput = (data) {
      _terminalService?.write(data);
    };
    
    // Setup resize routing: from terminal view -> websocket
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      _terminalService?.resize(width, height);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  void _connect() async {
    final appState = context.read<AppState>();
    _terminalService = TerminalService(appState, widget.hostId.toString());
    
    _terminalService?.onData = (text) {
      terminal.write(text);
    };

    final success = await _terminalService?.connect() ?? false;
    if (!success) {
      terminal.write('\r\nFailed to get WS ticket or connect.\r\n');
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _terminalService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
            },
            child: ColoredBox(
              color: Colors.black, // true black for terminal
              child: TerminalView(
                terminal,
                controller: terminalController,
                focusNode: _focusNode,
                hardwareKeyboardOnly: !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux),
                backgroundOpacity: 1.0,
                textStyle: const TerminalStyle(
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        // Termius-style virtual keyboard bar
        _buildVirtualKeyboard(),
      ],
    );
  }

  Widget _buildVirtualKeyboard() {
    return Container(
      color: const Color(0xFF2D2D2D),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildKey('Esc', '\x1b'),
          _buildKey('Tab', '\t'),
          _buildKey('Ctrl+C', '\x03'),
          _buildKey('Ctrl+D', '\x04'),
          _buildKey('Ctrl+Z', '\x1A'),
          _buildKey('↑', '\x1b[A'),
          _buildKey('↓', '\x1b[B'),
          _buildKey('←', '\x1b[D'),
          _buildKey('→', '\x1b[C'),
          _buildKey('|', '|'),
          _buildKey('/', '/'),
          _buildKey('-', '-'),
        ],
      ),
    );
  }

  Widget _buildKey(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Material(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            _terminalService?.write(value);
            _focusNode.requestFocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
