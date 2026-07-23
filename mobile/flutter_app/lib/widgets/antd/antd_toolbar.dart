import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdToolbar 用于页面顶部的横向工具栏，对齐 Web 端各页面的工具区视觉。
///
/// 视觉参考：白底 / 暗模式深底，1px 下边框，左右两组子元素，
/// 之间自动撑开。在窄屏下整体可水平滚动，避免 RIGHT/BOTTOM 溢出。
class AntdToolbar extends StatelessWidget {
  const AntdToolbar({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.height = 44,
    this.padding,
    this.spacing = 8,
    this.bordered = true,
    this.background,
  });

  final List<Widget> leading;
  final List<Widget> trailing;
  final double height;
  final EdgeInsetsGeometry? padding;
  final double spacing;
  final bool bordered;
  final Color? background;

  Widget _spaced(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) out.add(SizedBox(width: spacing));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: out);
  }

  @override
  Widget build(BuildContext context) {
    final bg = background ?? AntdTokens.containerColor(context);
    final borderColor = AntdTokens.borderSecondaryColor(context);
    final resolvedPadding = padding ??
        EdgeInsets.symmetric(
          horizontal: AntdTokens.cardBodyPadding(context),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: bg,
            border: bordered
                ? Border(bottom: BorderSide(color: borderColor))
                : null,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: availableWidth),
              child: Padding(
                padding: resolvedPadding,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _spaced(leading),
                    if (trailing.isNotEmpty) _spaced(trailing),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
