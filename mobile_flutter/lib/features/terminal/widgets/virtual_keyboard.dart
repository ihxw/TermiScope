import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

class VirtualKeyboard extends StatelessWidget {
  final Terminal terminal;

  const VirtualKeyboard({super.key, required this.terminal});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _buildKey('Esc', TerminalKey.escape),
          _buildKey('Tab', TerminalKey.tab),
          _buildKey('Ctrl', null, isModifier: true),
          _buildKey('Alt', null, isModifier: true),
          _buildKey('▲', TerminalKey.arrowUp),
          _buildKey('▼', TerminalKey.arrowDown),
          _buildKey('◀', TerminalKey.arrowLeft),
          _buildKey('▶', TerminalKey.arrowRight),
          _buildKey('Home', TerminalKey.home),
          _buildKey('End', TerminalKey.end),
          _buildKey('PgUp', TerminalKey.pageUp),
          _buildKey('PgDn', TerminalKey.pageDown),
        ],
      ),
    );
  }

  Widget _buildKey(String label, TerminalKey? key, {bool isModifier = false}) {
    // Note: handling modifiers properly requires state (toggle) or holding.
    // Xterm.dart usually handles virtual keys directly via keyDown/keyUp.
    // For simple modifiers like Ctrl+C, we might need a composite approach.
    // Since xterm 3.0/4.0, input handling might differ.
    // For now, let's implement simple key presses.
    // Modifiers are more complex without state.
    // Let's just implement basic keys for navigation first.

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Material(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: () {
            if (key != null) {
              terminal.keyInput(key);
            } else if (label == 'Ctrl') {
              // Toggle Ctrl? Or send commonly used Ctrl combinations?
              // Creating a proper modifier toggle needs state.
              // We will skip complex modifiers for this first pass.
            }
          },
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
