import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdSplitPane 可拖拽分割的面板。
///
/// 支持水平（左右两栏）或垂直（上下两栏）分割，中间拖拽手柄可调整比例。
class AntdSplitPane extends StatefulWidget {
  const AntdSplitPane({
    super.key,
    this.direction = Axis.horizontal,
    this.initialRatio = 0.5,
    this.minRatio = 0.15,
    this.maxRatio = 0.85,
    this.dividerWidth = 6,
    required this.first,
    required this.second,
  });

  final Axis direction;
  final double initialRatio;
  final double minRatio;
  final double maxRatio;
  final double dividerWidth;
  final Widget first;
  final Widget second;

  @override
  State<AntdSplitPane> createState() => _AntdSplitPaneState();
}

class _AntdSplitPaneState extends State<AntdSplitPane> {
  late double _ratio;

  @override
  void initState() {
    super.initState();
    _ratio = widget.initialRatio;
  }

  void _onDrag(DragUpdateDetails details, double total) {
    if (total <= 0) return;
    final delta = widget.direction == Axis.horizontal
        ? details.delta.dx
        : details.delta.dy;
    setState(() {
      _ratio = (_ratio + delta / total).clamp(
        widget.minRatio,
        widget.maxRatio,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    final dividerColor =
        isDark ? const Color(0xFF303030) : const Color(0xFFE8E8E8);

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = widget.direction == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final firstSize = (total * _ratio).clamp(0.0, total);

        final firstWidget = SizedBox(
          width: widget.direction == Axis.horizontal ? firstSize : null,
          height: widget.direction == Axis.vertical ? firstSize : null,
          child: widget.first,
        );

        final divider = MouseRegion(
          cursor: widget.direction == Axis.horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: widget.direction == Axis.horizontal
                ? (d) => _onDrag(d, total)
                : null,
            onVerticalDragUpdate: widget.direction == Axis.vertical
                ? (d) => _onDrag(d, total)
                : null,
            child: Container(
              width: widget.direction == Axis.horizontal
                  ? widget.dividerWidth
                  : null,
              height: widget.direction == Axis.vertical
                  ? widget.dividerWidth
                  : null,
              color: dividerColor,
            ),
          ),
        );

        final secondWidget = Expanded(child: widget.second);

        if (widget.direction == Axis.horizontal) {
          return Row(children: [firstWidget, divider, secondWidget]);
        }
        return Column(children: [firstWidget, divider, secondWidget]);
      },
    );
  }
}
