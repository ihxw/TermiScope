import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdSpin 加载指示器。
///
/// - `inline=true` 时不撑满父级，仅显示一圈圆形进度
/// - 默认显示在父级居中，并可配 [tip] 文案
class AntdSpin extends StatelessWidget {
  const AntdSpin({
    super.key,
    this.tip,
    this.size = 20,
    this.inline = false,
    this.color,
  });

  final String? tip;
  final double size;
  final bool inline;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor:
            AlwaysStoppedAnimation<Color>(color ?? AntdTokens.primary),
      ),
    );

    if (inline) {
      if (tip == null || tip!.isEmpty) return indicator;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(width: 8),
          Text(tip!,
              style: TextStyle(
                fontSize: AntdTokens.fontSize,
                color: AntdTokens.secondaryTextColor(context),
              )),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          if (tip != null && tip!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tip!,
                style: TextStyle(
                  fontSize: AntdTokens.fontSize,
                  color: AntdTokens.secondaryTextColor(context),
                )),
          ],
        ],
      ),
    );
  }
}
