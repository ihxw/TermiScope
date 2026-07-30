import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdStatusBadge 状态圆点标签。
///
/// 对齐 ant-design 的 Badge status 视觉效果：
/// - 左侧实心圆点 + 文本
class AntdStatusBadge extends StatelessWidget {
  const AntdStatusBadge({
    super.key,
    required this.status,
    this.text,
    this.size = 8,
  });

  final AntdStatusBadgeStatus status;
  final String? text;
  final double size;

  Color _color(BuildContext context) {
    switch (status) {
      case AntdStatusBadgeStatus.success:
      case AntdStatusBadgeStatus.online:
        return AntdTokens.success;
      case AntdStatusBadgeStatus.error:
      case AntdStatusBadgeStatus.offline:
        return AntdTokens.error;
      case AntdStatusBadgeStatus.warning:
        return AntdTokens.warning;
      case AntdStatusBadgeStatus.processing:
        return AntdTokens.primary;
      case AntdStatusBadgeStatus.defaultStatus:
      case AntdStatusBadgeStatus.unknown:
        return AntdTokens.secondaryTextColor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = _color(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        if (text != null && text!.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            text!,
            style: TextStyle(
              fontSize: AntdTokens.fontSize,
              color: AntdTokens.textColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

enum AntdStatusBadgeStatus {
  success,
  error,
  warning,
  processing,
  defaultStatus,
  online,
  offline,
  unknown,
}
