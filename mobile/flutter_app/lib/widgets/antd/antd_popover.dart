import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdPopover 轻量弹出层，复刻 ant-design `Popover`。
///
/// 点击 [child] 后在下方弹出带箭头的内容卡片。比 `Tooltip` 内容更丰富。
class AntdPopover extends StatefulWidget {
  const AntdPopover({
    super.key,
    required this.child,
    required this.content,
    this.title,
    this.width,
  });

  final Widget child;
  final Widget content;
  final Widget? title;
  final double? width;

  @override
  State<AntdPopover> createState() => _AntdPopoverState();
}

class _AntdPopoverState extends State<AntdPopover> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  bool _open = false;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _open = true;
      _show();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _open = false;
  }

  void _show() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.transparent)),
            Positioned(
              left: offset.dx + size.width / 2 - (widget.width ?? 240) / 2,
              top: offset.dy + size.height + 8,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {},
                  child: CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    offset: Offset(0, size.height + 8),
                    child: Container(
                      width: widget.width ?? 240,
                      decoration: BoxDecoration(
                        color: AntdTokens.containerColor(context),
                        borderRadius:
                            BorderRadius.circular(AntdTokens.radiusLG),
                        border: Border.all(
                            color: AntdTokens.borderSecondaryColor(context)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(
                                AntdTokens.isDark(context) ? 80 : 15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.title != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  fontSize: AntdTokens.fontSize,
                                  fontWeight: FontWeight.w600,
                                  color: AntdTokens.textColor(context),
                                ),
                                child: widget.title!,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: widget.content,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_entry!);
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: widget.child,
      ),
    );
  }
}
