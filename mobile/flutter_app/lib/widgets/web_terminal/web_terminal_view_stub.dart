import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

class WebTerminalController {
  void write(String data) {}
  void focus() {}
  void dispose() {}
}

class WebTerminalView extends StatelessWidget {
  const WebTerminalView({
    super.key,
    required this.controller,
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.onData,
    required this.onResize,
  });

  final WebTerminalController controller;
  final TerminalTheme theme;
  final String fontFamily;
  final double fontSize;
  final ValueChanged<String> onData;
  final void Function(int cols, int rows) onResize;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
