import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_button.dart';
import 'antd_status_badge.dart';

/// AntdMetricCard 监控指标卡片，复刻 ant-design 统计数值组件 `Statistic` + 卡片。
///
/// 用于监控仪表盘：大数字 + 标题 + 图标 + 操作按钮。
class AntdMetricCard extends StatelessWidget {
  const AntdMetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.status,
    this.statusText,
    this.onTap,
    this.actions = const [],
    this.child,
  });

  /// 标题（如 CPU、RAM）。
  final String title;

  /// 主数值字符串。
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final AntdStatusBadgeStatus? status;
  final String? statusText;
  final VoidCallback? onTap;

  /// 底部操作按钮列表。
  final List<AntdButton> actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);

    // Status dot + text in top-right
    Widget? statusWidget;
    if (status != null && statusText != null) {
      Color dotColor;
      switch (status!) {
        case AntdStatusBadgeStatus.online:
        case AntdStatusBadgeStatus.success:
          dotColor = AntdTokens.success;
        case AntdStatusBadgeStatus.offline:
        case AntdStatusBadgeStatus.error:
          dotColor = AntdTokens.error;
        case AntdStatusBadgeStatus.warning:
          dotColor = AntdTokens.warning;
        case AntdStatusBadgeStatus.processing:
          dotColor = AntdTokens.primary;
        default:
          dotColor = AntdTokens.secondaryTextColor(context);
      }
      statusWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: dotColor.withAlpha(isDark ? 40 : 25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              statusText!,
              style: TextStyle(
                fontSize: AntdTokens.fontSizeSM,
                fontWeight: FontWeight.w600,
                color: dotColor,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AntdTokens.containerColor(context),
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
          border: Border.all(color: AntdTokens.borderSecondaryColor(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: AntdTokens.fontSize,
                        fontWeight: FontWeight.w600,
                        color: AntdTokens.textColor(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (statusWidget != null) statusWidget,
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 32, color: iconColor ?? AntdTokens.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AntdTokens.textColor(context),
                            height: 1.2,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: AntdTokens.fontSizeSM,
                              color: AntdTokens.secondaryTextColor(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Child content (progress bars etc.)
            if (child != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: child!,
              ),

            // Actions
            if (actions.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
