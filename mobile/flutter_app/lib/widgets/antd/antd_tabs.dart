import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdTabsItem 表示一个 tab 项。
class AntdTabsItem {
  const AntdTabsItem({
    required this.key,
    required this.label,
    this.icon,
    this.closable = false,
    this.recording = false,
  });

  final String key;
  final Widget label;
  final IconData? icon;

  /// 是否显示关闭按钮（终端编辑器风格）。
  final bool closable;

  /// 是否为录制状态，标题前显示红点。
  final bool recording;
}

/// AntdTabs 复刻 Web 端 ant-design / VS Code 风格的横向 tab。
///
/// - 默认风格：底部下划线
/// - `editor: true` 时切换为 VS Code 编辑器分页风格（顶部彩条 + 关闭按钮）
class AntdTabs extends StatelessWidget {
  const AntdTabs({
    super.key,
    required this.items,
    required this.activeKey,
    required this.onChange,
    this.onClose,
    this.editor = false,
    this.height,
    this.background,
  });

  final List<AntdTabsItem> items;
  final String? activeKey;
  final ValueChanged<String> onChange;
  final ValueChanged<String>? onClose;
  final bool editor;
  final double? height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    if (editor) {
      return _buildEditorTabs(context);
    }
    return _buildLineTabs(context);
  }

  Widget _buildLineTabs(BuildContext context) {
    final fg = AntdTokens.textColor(context);
    final secondary = AntdTokens.secondaryTextColor(context);
    final borderColor = AntdTokens.borderSecondaryColor(context);

    return Container(
      height: height ?? 40,
      decoration: BoxDecoration(
        color: background ?? AntdTokens.containerColor(context),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((item) {
            final selected = item.key == activeKey;
            final color = selected ? AntdTokens.primary : secondary;
            return InkWell(
              onTap: () => onChange(item.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? AntdTokens.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 14, color: color),
                      const SizedBox(width: 6),
                    ],
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: AntdTokens.fontSize,
                        color: selected ? AntdTokens.primary : fg,
                      ),
                      child: item.label,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEditorTabs(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    final navColor = isDark ? const Color(0xFF252526) : const Color(0xFFF3F3F3);
    final borderColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFD4D4D4);
    final activeBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final inactiveBg =
        isDark ? const Color(0xFF2D2D2D) : const Color(0xFFECECEC);
    final activeText = isDark ? Colors.white : const Color(0xFF333333);
    final inactiveText =
        isDark ? const Color(0xFF969696) : const Color(0xFF616161);
    final closeColor =
        isDark ? const Color(0xFFCCCCCC) : const Color(0xFF999999);
    final tabHeight = height ?? 28;

    return Container(
      height: tabHeight + 1,
      width: double.infinity,
      decoration: BoxDecoration(
        color: navColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = item.key == activeKey;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChange(item.key),
            child: Container(
              height: tabHeight,
              padding: const EdgeInsets.fromLTRB(12, 3, 8, 4),
              decoration: BoxDecoration(
                color: selected ? activeBg : inactiveBg,
                border: Border(
                  top: BorderSide(
                    color: selected ? AntdTokens.primary : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.recording) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AntdTokens.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: selected ? activeText : inactiveText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: item.label,
                    ),
                  ),
                  if (item.closable) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(2),
                      onTap: () => onClose?.call(item.key),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child:
                            Icon(Icons.close, size: 10, color: closeColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
