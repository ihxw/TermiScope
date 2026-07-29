import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdSpace 复刻 ant-design `a-space`，用于在子元素之间提供统一间距。
class AntdSpace extends StatelessWidget {
  const AntdSpace({
    super.key,
    required this.children,
    this.direction = Axis.horizontal,
    this.size = AntdTokens.marginSM,
    this.wrap = false,
    this.align = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.min,
  });

  final List<Widget> children;
  final Axis direction;
  final double size;
  final bool wrap;
  final CrossAxisAlignment align;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    if (wrap) {
      return Wrap(
        direction: direction,
        spacing: size,
        runSpacing: size,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }

    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i != children.length - 1) {
        separated.add(direction == Axis.horizontal
            ? SizedBox(width: size)
            : SizedBox(height: size));
      }
    }

    if (direction == Axis.horizontal) {
      return Row(
        mainAxisSize: mainAxisSize,
        crossAxisAlignment: align,
        children: separated,
      );
    }
    return Column(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: align,
      children: separated,
    );
  }
}

/// AntdDivider 分割线，复刻 ant-design `a-divider`。
class AntdDivider extends StatelessWidget {
  const AntdDivider({
    super.key,
    this.direction = Axis.horizontal,
    this.text,
    this.thickness = 1,
  });

  final Axis direction;
  final String? text;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final color = AntdTokens.borderSecondaryColor(context);
    if (direction == Axis.vertical) {
      return Container(width: thickness, color: color);
    }
    if (text == null || text!.isEmpty) {
      return Container(
        height: thickness,
        margin: const EdgeInsets.symmetric(vertical: 12),
        color: color,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: thickness, color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              text!,
              style: TextStyle(
                fontSize: AntdTokens.fontSize,
                color: AntdTokens.textColor(context),
              ),
            ),
          ),
          Expanded(child: Container(height: thickness, color: color)),
        ],
      ),
    );
  }
}
