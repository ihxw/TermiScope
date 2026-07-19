import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdSegmented 分段控制器，复刻 ant-design `Segmented`。
///
/// 水平方向的分段按钮组，选中项以白底/暗底 + 主色文字 + 阴影表现。
class AntdSegmented<T extends Object> extends StatelessWidget {
  const AntdSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.disabled = false,
    this.block = false,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final bool disabled;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final entries = options.entries.toList();
    final isDark = AntdTokens.isDark(context);
    final bg = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5);
    final selectedBg = isDark ? const Color(0xFF141414) : Colors.white;
    final fg = AntdTokens.textColor(context);

    final row = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      children: List.generate(entries.length, (i) {
        final entry = entries[i];
        final selected = entry.key == value;
        return Expanded(
          child: MouseRegion(
            cursor: disabled
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: disabled ? null : () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withAlpha(80)
                                : Colors.black.withAlpha(20),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: AntdTokens.fontSizeSM,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AntdTokens.primary : fg,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: row,
    );
  }
}
