import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdCard 复刻 ant-design-vue `a-card` 的卡片容器。
///
/// - 默认带 1px 边框、8px 圆角
/// - 可选 [title] / [extra] 形成头部，固定高度 `cardHeaderHeight`
/// - 默认 body padding 为 12（小屏 8）
/// - `bordered=false` 时无外边框（用于嵌套场景）
class AntdCard extends StatelessWidget {
  const AntdCard({
    super.key,
    this.title,
    this.extra,
    this.bordered = true,
    this.padding,
    this.headerPadding,
    this.bodyColor,
    required this.child,
  });

  final Widget? title;
  final Widget? extra;
  final bool bordered;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? headerPadding;
  final Color? bodyColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || extra != null;
    final defaultBodyPadding = EdgeInsets.all(AntdTokens.cardBodyPadding(context));

    Widget? header;
    if (hasHeader) {
      header = Container(
        height: AntdTokens.cardHeaderHeight,
        padding: headerPadding ??
            const EdgeInsets.symmetric(horizontal: AntdTokens.padding),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AntdTokens.borderSecondaryColor(context),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            if (title != null)
              Expanded(
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontSize: AntdTokens.fontSizeLG,
                    fontWeight: FontWeight.w600,
                    color: AntdTokens.textColor(context),
                  ),
                  child: title!,
                ),
              )
            else
              const Spacer(),
            if (extra != null) extra!,
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: bodyColor ?? AntdTokens.containerColor(context),
        borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
        border: bordered
            ? Border.all(color: AntdTokens.borderSecondaryColor(context))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) header,
          Padding(
            padding: padding ?? defaultBodyPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
