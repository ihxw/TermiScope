import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// 提示类型，对齐 ant-design 的 `a-alert` type。
enum AntdAlertType { info, success, warning, error }

/// AntdAlert 提示条，复刻 ant-design `a-alert` 视觉。
class AntdAlert extends StatelessWidget {
  const AntdAlert({
    super.key,
    this.type = AntdAlertType.info,
    this.message,
    this.description,
    this.showIcon = true,
    this.closable = false,
    this.onClose,
    this.action,
  });

  final AntdAlertType type;
  final String? message;
  final String? description;
  final bool showIcon;
  final bool closable;
  final VoidCallback? onClose;
  final Widget? action;

  Color _color() {
    switch (type) {
      case AntdAlertType.info:
        return AntdTokens.primary;
      case AntdAlertType.success:
        return AntdTokens.success;
      case AntdAlertType.warning:
        return AntdTokens.warning;
      case AntdAlertType.error:
        return AntdTokens.error;
    }
  }

  IconData _icon() {
    switch (type) {
      case AntdAlertType.info:
        return Icons.info_outline;
      case AntdAlertType.success:
        return Icons.check_circle_outline;
      case AntdAlertType.warning:
        return Icons.warning_amber_outlined;
      case AntdAlertType.error:
        return Icons.error_outline;
    }
  }

  Color _bg(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    switch (type) {
      case AntdAlertType.info:
        return isDark ? const Color(0xFF111A2C) : const Color(0xFFE6F7FF);
      case AntdAlertType.success:
        return isDark ? const Color(0xFF162312) : const Color(0xFFF6FFED);
      case AntdAlertType.warning:
        return isDark ? const Color(0xFF2B2111) : const Color(0xFFFFFBE6);
      case AntdAlertType.error:
        return isDark ? const Color(0xFF2A1215) : const Color(0xFFFFF1F0);
    }
  }

  Color _border(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    switch (type) {
      case AntdAlertType.info:
        return isDark ? const Color(0xFF153450) : const Color(0xFF91D5FF);
      case AntdAlertType.success:
        return isDark ? const Color(0xFF274916) : const Color(0xFFB7EB8F);
      case AntdAlertType.warning:
        return isDark ? const Color(0xFF594214) : const Color(0xFFFFE58F);
      case AntdAlertType.error:
        return isDark ? const Color(0xFF58181C) : const Color(0xFFFFA39E);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final hasDescription = description != null && description!.isNotEmpty;
    final hasMessage = message != null && message!.isNotEmpty;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: hasDescription ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: _bg(context),
        border: Border.all(color: _border(context)),
        borderRadius: BorderRadius.circular(AntdTokens.radius),
      ),
      child: Row(
        crossAxisAlignment:
            hasDescription ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (showIcon) ...[
            Icon(_icon(), color: color, size: hasDescription ? 20 : 14),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasMessage)
                  Text(
                    message!,
                    style: TextStyle(
                      fontSize: hasDescription
                          ? AntdTokens.fontSizeLG
                          : AntdTokens.fontSize,
                      fontWeight: hasDescription ? FontWeight.w600 : FontWeight.w400,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                if (hasDescription) ...[
                  if (hasMessage) const SizedBox(height: 4),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action!,
          ],
          if (closable)
            GestureDetector(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
