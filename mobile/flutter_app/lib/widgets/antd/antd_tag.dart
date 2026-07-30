import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdTag 标签，复刻 ant-design `a-tag`。
///
/// 提供两种模式：
/// - 预设 [AntdTagPreset.success] / `processing` / `error` / `warning` / `default`
/// - 自定义 [color]：会作为前景色与边框色，背景使用 `color.withAlpha(20)`
class AntdTag extends StatelessWidget {
  const AntdTag({
    super.key,
    this.preset = AntdTagPreset.defaultStyle,
    this.color,
    this.icon,
    this.bordered = true,
    required this.label,
  });

  final AntdTagPreset preset;
  final Color? color;
  final IconData? icon;
  final bool bordered;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);

    Color fg;
    Color bg;
    Color border;

    if (color != null) {
      fg = color!;
      bg = color!.withAlpha(isDark ? 40 : 24);
      border = color!.withAlpha(isDark ? 100 : 80);
    } else {
      switch (preset) {
        case AntdTagPreset.success:
          fg = AntdTokens.success;
          bg = isDark ? const Color(0xFF162312) : const Color(0xFFF6FFED);
          border = isDark ? const Color(0xFF274916) : const Color(0xFFB7EB8F);
          break;
        case AntdTagPreset.processing:
          fg = AntdTokens.primary;
          bg = isDark ? const Color(0xFF111A2C) : const Color(0xFFE6F7FF);
          border = isDark ? const Color(0xFF153450) : const Color(0xFF91D5FF);
          break;
        case AntdTagPreset.error:
          fg = AntdTokens.error;
          bg = isDark ? const Color(0xFF2A1215) : const Color(0xFFFFF1F0);
          border = isDark ? const Color(0xFF58181C) : const Color(0xFFFFA39E);
          break;
        case AntdTagPreset.warning:
          fg = AntdTokens.warning;
          bg = isDark ? const Color(0xFF2B2111) : const Color(0xFFFFFBE6);
          border = isDark ? const Color(0xFF594214) : const Color(0xFFFFE58F);
          break;
        case AntdTagPreset.defaultStyle:
          fg = AntdTokens.textColor(context);
          bg = isDark ? AntdTokens.darkContainerSecondary : const Color(0xFFFAFAFA);
          border = AntdTokens.borderColor(context);
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: bordered ? Border.all(color: border, width: 1) : null,
        borderRadius: BorderRadius.circular(AntdTokens.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: AntdTokens.fontSizeSM,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

enum AntdTagPreset { defaultStyle, success, processing, error, warning }
