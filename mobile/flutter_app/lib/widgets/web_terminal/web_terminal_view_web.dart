// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

class WebTerminalController {
  WebTerminalController() : viewId = 'termiscope-terminal-${_nextId++}';

  static int _nextId = 0;
  final String viewId;

  void write(String data) {
    js_util.callMethod(_bridge, 'write', [viewId, data]);
  }

  void focus() {
    js_util.callMethod(_bridge, 'focus', [viewId]);
  }

  void dispose() {
    js_util.callMethod(_bridge, 'dispose', [viewId]);
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
        final element = html.DivElement()
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
      js_util.callMethod(_bridge, 'update', [
        widget.controller.viewId,
        _options(),
      ]);
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  void _create(int platformViewId) {
    if (!mounted || _created) return;
    final element = ui_web.platformViewRegistry.getViewById(platformViewId);
    if (element is html.Element) {
      element.id = widget.controller.viewId;
    }
    _created = true;
    final created = js_util.callMethod<bool>(_bridge, 'create', [
      widget.controller.viewId,
      _options(),
    ]);
    if (!created) {
      _created = false;
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () {
          if (mounted) _create(platformViewId);
        },
      );
    }
  }

  Object _options() {
    return js_util.jsify({
      'fontFamily': "'${widget.fontFamily}', monospace",
      'fontSize': widget.fontSize,
      'theme': _themeToMap(widget.theme),
      'onData': js_util.allowInterop((String data) {
        widget.onData(data);
      }),
      'onResize': js_util.allowInterop((int cols, int rows) {
        widget.onResize(cols, rows);
      }),
    });
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
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      viewType: widget.controller.viewId,
      onPlatformViewCreated: _create,
    );
  }
}

Object get _bridge => js_util.getProperty(html.window, 'termiScopeTerminal');
