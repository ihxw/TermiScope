import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../../data/services/api_service.dart';
import '../../data/services/terminal_service.dart';

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
  final TerminalController _terminalController = TerminalController();
  final FocusNode _focusNode = FocusNode(); // Add FocusNode
  StreamSubscription? _outputSubscription;
  StreamSubscription? _statusSubscription;
  String _status = 'Initializing...';
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);

    // Inject ApiService
    _service = TerminalService(Provider.of<ApiService>(context, listen: false));

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
          // output initial prompt if needed
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
      if (mounted) {
        // Slight delay to ensure view is ready for input client registration
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _focusNode.requestFocus();
        });
      }
    });
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _statusSubscription?.cancel();
    _service.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(
              _status,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else {
                _focusNode.requestFocus();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              _terminal,
              controller: _terminalController,
              autofocus: false,
              focusNode: _focusNode,
              backgroundOpacity: 1,
              keyboardType: TextInputType
                  .visiblePassword, // Optimization for terminal input
              // onResize removed from TerminalView
            ),
          ),
          _buildVirtualToolbar(),
        ],
      ),
    );
  }

  Widget _buildVirtualToolbar() {
    return Container(
      color: Colors.grey[200],
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _toolbarButton('Esc', '\x1b'),
          _toolbarButton('Tab', '\t'),
          _toolbarButton('Ctrl+C', '\x03'),
          _toolbarButton('Ctrl+D', '\x04'),
          _toolbarButton('Up', '\x1b[A'),
          _toolbarButton('Down', '\x1b[B'),
          _toolbarButton('Left', '\x1b[D'),
          _toolbarButton('Right', '\x1b[C'),
          _toolbarButton('/', '/'),
          _toolbarButton('-', '-'),
          _toolbarButton('|', '|'),
        ],
      ),
    );
  }

  Widget _toolbarButton(String label, String keySent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(40, 36),
        ),
        onPressed: () {
          _service.sendInput(keySent);
        },
        child: Text(label),
      ),
    );
  }
}
