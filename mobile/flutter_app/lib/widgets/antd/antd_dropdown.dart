import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdDropdownItem 表示下拉菜单中的一项。
class AntdDropdownItem<T> {
  const AntdDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.danger = false,
    this.divider = false,
    this.disabled = false,
  });

  /// 选项值。
  final T value;

  /// 显示文本。
  final String label;

  /// 行首图标。
  final IconData? icon;

  /// 是否为危险样式（红色）。
  final bool danger;

  /// 在该项之前插入分隔线。
  final bool divider;

  /// 禁用该菜单项，同时保留其说明文字。
  final bool disabled;
}

/// 自定义渲染项，用于 [AntdDropdown.customItems]。
class AntdDropdownCustomEntry<T> {
  const AntdDropdownCustomEntry({
    required this.value,
    required this.builder,
    this.divider = false,
  });

  final T value;
  final WidgetBuilder builder;
  final bool divider;
}

/// AntdDropdown 复刻 ant-design `a-dropdown` 的菜单触发组件。
///
/// 通过 [PopupMenuButton] 实现，但视觉上对齐 ant-design：
/// 圆角 4、白底/暗底、1px 边框、悬停浅蓝高亮。
class AntdDropdown<T> extends StatelessWidget {
  const AntdDropdown({
    super.key,
    required this.child,
    required this.items,
    required this.onSelected,
    this.tooltip,
    this.offset = const Offset(0, 8),
  });

  /// 触发器。
  final Widget child;

  /// 菜单项列表。
  final List<AntdDropdownItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);

    return PopupMenuButton<T>(
      tooltip: tooltip ?? '',
      padding: EdgeInsets.zero,
      offset: offset,
      color: AntdTokens.containerColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AntdTokens.radiusLG),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      elevation: isDark ? 8 : 4,
      onSelected: onSelected,
      itemBuilder: (context) {
        final children = <PopupMenuEntry<T>>[];
        for (final item in items) {
          if (item.divider) {
            children.add(const PopupMenuDivider());
            if (item.label.isEmpty && item.icon == null) continue;
          }
          children.add(
            PopupMenuItem<T>(
              value: item.value,
              enabled: !item.disabled,
              height: 32,
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(
                      item.icon,
                      size: 14,
                      color: item.disabled
                          ? AntdTokens.disabledTextColor(context)
                          : item.danger
                              ? AntdTokens.error
                              : AntdTokens.textColor(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      color: item.disabled
                          ? AntdTokens.disabledTextColor(context)
                          : item.danger
                              ? AntdTokens.error
                              : AntdTokens.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return children;
      },
      child: AbsorbPointer(child: child),
    );
  }
}
