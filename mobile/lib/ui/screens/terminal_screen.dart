import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../../services/terminal_service.dart';
import '../../models/ssh_host.dart';

class TerminalScreen extends StatefulWidget {
  final String sessionId;
  final SSHHost host;

  const TerminalScreen({
    super.key,
    required this.sessionId,
    required this.host,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late Terminal _terminal;
  late TerminalController _terminalController;
  final TerminalService _terminalService = TerminalService();
  bool _isConnected = false;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal();
    _terminalController = TerminalController();


    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToHost();
    });
  }

  Future<void> _connectToHost() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connected = await _terminalService.connectToHost(widget.host, _terminal);
      if (connected) {
        setState(() {
          _isConnected = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to connect to ${widget.host.hostname}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to host: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _terminalService.disconnect();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.terminal} - ${widget.host.name}'),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.sync : Icons.refresh),
            onPressed: _connectToHost,
            tooltip: _isConnected ? l10n.reconnect : l10n.connect,
          ),
          PopupMenuButton(
            onSelected: (value) {
              if (value == 'clear') {
                _terminal.buffer.clear();
              } else if (value == 'copy') {
                _copySelection();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    const Icon(Icons.clear_all, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.clearTerminal),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    const Icon(Icons.copy, size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.copySelection),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading)
              LinearProgressIndicator(
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
              )
            else if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                    TextButton(
                      onPressed: _connectToHost,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                color: Colors.black,
                child: TerminalView(
                  _terminal,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendCtrlC,
        tooltip: 'Send Ctrl+C',
        child: const Icon(Icons.stop),
      ),
    );
  }

  void _copySelection() {
    final selection = '';
    if (selection.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selection));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.copiedToClipboard)),
      );
    }
  }

  void _sendCtrlC() {
    _terminalService.sendCommand('\x03'); // Send Ctrl+C (ETX)
  }
}