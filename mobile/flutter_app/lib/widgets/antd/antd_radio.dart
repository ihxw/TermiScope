import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdRadioOption 表示 [AntdRadioGroup] 的一项。
class AntdRadioOption<T> {
  const AntdRadioOption({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

/// AntdRadioGroup 复刻 ant-design "Radio.Group" 的 button 样式。
///
/// - 选项以分段按钮的形式横向并排
/// - 选中项前景色与边框使用 [AntdTokens.primary]
/// - 暗色模式下使用容器色填充
class AntdRadioGroup<T> extends StatelessWidget {
  const AntdRadioGroup({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.disabled = false,
    this.size = AntdRadioSize.middle,
  });

  final T value;
  final List<AntdRadioOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool disabled;
  final AntdRadioSize size;

  double get _height => size == AntdRadioSize.small
      ? AntdTokens.controlHeightSM
      : AntdTokens.controlHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    final defaultBg = AntdTokens.containerColor(context);
    final selectedBg = isDark
        ? AntdTokens.primary.withAlpha(40)
        : AntdTokens.primary.withAlpha(20);
    final defaultBorder = AntdTokens.borderColor(context);
    final defaultFg = AntdTokens.textColor(context);

    return Wrap(
      spacing: 0,
      runSpacing: 6,
      children: List.generate(options.length, (index) {
        final option = options[index];
        final selected = option.value == value;
        final isFirst = index == 0;
        final isLast = index == options.length - 1;
        final radius = BorderRadius.horizontal(
          left: Radius.circular(isFirst ? AntdTokens.radius : 0),
          right: Radius.circular(isLast ? AntdTokens.radius : 0),
        );

        return MouseRegion(
          cursor: disabled
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: disabled ? null : () => onChanged(option.value),
            child: Container(
              height: _height,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? selectedBg : defaultBg,
                border: Border(
                  left: BorderSide(
                    color: selected ? AntdTokens.primary : defaultBorder,
                  ),
                  right: BorderSide(
                    color: selected ? AntdTokens.primary : defaultBorder,
                  ),
                  top: BorderSide(
                    color: selected ? AntdTokens.primary : defaultBorder,
                  ),
                  bottom: BorderSide(
                    color: selected ? AntdTokens.primary : defaultBorder,
                  ),
                ),
                borderRadius: radius,
              ),
              child: Text(
                option.label,
                style: TextStyle(
                  fontSize: AntdTokens.fontSize,
                  color: disabled
                      ? AntdTokens.disabledTextColor(context)
                      : (selected ? AntdTokens.primary : defaultFg),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

enum AntdRadioSize { small, middle }
