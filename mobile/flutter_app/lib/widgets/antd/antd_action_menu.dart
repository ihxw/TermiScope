import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdActionMenuItem 表示 [AntdActionMenu] 中的一项操作。
class AntdActionMenuItem {
  const AntdActionMenuItem({
    required this.key,
    required this.label,
    this.icon,
    this.danger = false,
    this.showDividerAfter = false,
  });

  final String key;
  final String label;
  final IconData? icon;
  final bool danger;
  final bool showDividerAfter;
}

/// AntdActionMenu 行操作菜单，常用于表格操作列。
///
/// 以 `...` 或自定义触发器弹出 [PopupMenuButton]，每个菜单项
/// 可通过 [onAction] 回调得到所选项 key。
class AntdActionMenu extends StatelessWidget {
  const AntdActionMenu({
    super.key,
    required this.items,
    this.onAction,
    this.icon,
    this.tooltip,
  });

  final List<AntdActionMenuItem> items;
  final ValueChanged<String>? onAction;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    return PopupMenuButton<String>(
      tooltip: tooltip ?? '',
      padding: EdgeInsets.zero,
      icon: Icon(
        icon ?? Icons.more_horiz,
        size: 18,
        color: AntdTokens.secondaryTextColor(context),
      ),
      color: AntdTokens.containerColor(context),
      elevation: isDark ? 8 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      offset: const Offset(0, 4),
      onSelected: onAction,
      itemBuilder: (ctx) {
        final entries = <PopupMenuEntry<String>>[];
        for (final item in items) {
          entries.add(
            PopupMenuItem<String>(
              value: item.key,
              height: 32,
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(
                      item.icon,
                      size: 14,
                      color: item.danger
                          ? AntdTokens.error
                          : AntdTokens.textColor(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      color: item.danger
                          ? AntdTokens.error
                          : AntdTokens.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
          );
          if (item.showDividerAfter) {
            entries.add(const PopupMenuDivider());
          }
        }
        return entries;
      },
    );
  }
}
