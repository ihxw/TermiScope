import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'package:xterm/xterm.dart';

@JS('termiScopeTerminal')
external _TerminalBridge get _bridge;

extension type _TerminalBridge(JSObject _) implements JSObject {
  external void write(String viewId, String data);
  external void focus(String viewId);
  external String getSelection(String viewId);
  external void clearSelection(String viewId);
  external void selectAll(String viewId);
  external void dispose(String viewId);
  external void update(String viewId, JSObject options);
  external bool create(String viewId, JSObject options);
}

@JS()
@anonymous
extension type _TerminalOptions._(JSObject _) implements JSObject {
  external factory _TerminalOptions({
    required String fontFamily,
    required double fontSize,
    required JSObject theme,
    required JSFunction onData,
    required JSFunction onResize,
  });
}

class WebTerminalController {
  WebTerminalController() : viewId = 'termiscope-terminal-${_nextId++}';

  static int _nextId = 0;
  final String viewId;

  void write(String data) {
    _bridge.write(viewId, data);
  }

  void focus() {
    _bridge.focus(viewId);
  }

  String getSelection() => _bridge.getSelection(viewId);

  void clearSelection() => _bridge.clearSelection(viewId);

  void selectAll() => _bridge.selectAll(viewId);

  void dispose() {
    _bridge.dispose(viewId);
  }
}

class WebTerminalView extends StatefulWidget {
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
  State<WebTerminalView> createState() => _WebTerminalViewState();
}

class _WebTerminalViewState extends State<WebTerminalView> {
  bool _created = false;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(
      widget.controller.viewId,
      (int viewId) {
        final element = web.HTMLDivElement()
          ..id = widget.controller.viewId
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.overflow = 'hidden';
        return element;
      },
    );
  }

  @override
  void didUpdateWidget(covariant WebTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_created) {
      _bridge.update(widget.controller.viewId, _options());
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  void _create(int _) {
    if (!mounted || _created) return;
    _created = true;
    final created = _bridge.create(widget.controller.viewId, _options());
    if (!created) {
      _created = false;
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () {
          if (mounted) _create(0);
        },
      );
    }
  }

  JSObject _options() {
    return _TerminalOptions(
      fontFamily: "'${widget.fontFamily}', monospace",
      fontSize: widget.fontSize,
      theme: _themeToMap(widget.theme).jsify() as JSObject,
      onData: ((String data) {
        widget.onData(data);
      }).toJS,
      onResize: ((int cols, int rows) {
        widget.onResize(cols, rows);
      }).toJS,
    );
  }

  Map<String, String> _themeToMap(TerminalTheme theme) {
    return {
      'background': _hex(theme.background),
      'foreground': _hex(theme.foreground),
      'cursor': _hex(theme.cursor),
      'selectionBackground': _hex(theme.selection),
      'black': _hex(theme.black),
      'red': _hex(theme.red),
      'green': _hex(theme.green),
      'yellow': _hex(theme.yellow),
      'blue': _hex(theme.blue),
      'magenta': _hex(theme.magenta),
      'cyan': _hex(theme.cyan),
      'white': _hex(theme.white),
      'brightBlack': _hex(theme.brightBlack),
      'brightRed': _hex(theme.brightRed),
      'brightGreen': _hex(theme.brightGreen),
      'brightYellow': _hex(theme.brightYellow),
      'brightBlue': _hex(theme.brightBlue),
      'brightMagenta': _hex(theme.brightMagenta),
      'brightCyan': _hex(theme.brightCyan),
      'brightWhite': _hex(theme.brightWhite),
    };
  }

  String _hex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: widget.controller.viewId,
      onPlatformViewCreated: _create,
    );
  }
}
