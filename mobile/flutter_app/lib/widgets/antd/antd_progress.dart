import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';

/// AntdProgress 进度条，复刻 ant-design `Progress` line 模式。
///
/// - [percent] 为 0-100 的数值
/// - [color] 自定义颜色，未提供时按百分比自动变色（<70 成功绿，<90 警告黄，≥90 错误红）
/// - [showInfo] 控制是否显示百分比文案
class AntdProgress extends StatelessWidget {
  const AntdProgress({
    super.key,
    required this.percent,
    this.color,
    this.showInfo = true,
    this.strokeWidth = 6,
    this.trailColor,
  });

  final double percent;
  final Color? color;
  final bool showInfo;
  final double strokeWidth;
  final Color? trailColor;

  Color _resolveColor() {
    if (color != null) return color!;
    if (percent >= 90) return AntdTokens.error;
    if (percent >= 70) return AntdTokens.warning;
    return AntdTokens.success;
  }

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0, 100);
    final c = _resolveColor();
    final trail = trailColor ??
        (AntdTokens.isDark(context)
            ? const Color(0xFF262626)
            : const Color(0xFFF5F5F5));

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(strokeWidth / 2),
            child: LinearProgressIndicator(
              value: pct / 100,
              backgroundColor: trail,
              valueColor: AlwaysStoppedAnimation<Color>(c),
              minHeight: strokeWidth,
            ),
          ),
        ),
        if (showInfo) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              '${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: AntdTokens.fontSizeSM,
                color: AntdTokens.secondaryTextColor(context),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// AntdProgressCircle 环形进度，用于仪表盘场景。
class AntdProgressCircle extends StatelessWidget {
  const AntdProgressCircle({
    super.key,
    required this.percent,
    this.size = 80,
    this.strokeWidth = 6,
    this.color,
    this.showInfo = true,
    this.label,
  });

  final double percent;
  final double size;
  final double strokeWidth;
  final Color? color;
  final bool showInfo;
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AntdTokens.primary;
    final pct = percent.clamp(0, 100);
    final isDark = AntdTokens.isDark(context);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: strokeWidth,
              backgroundColor: isDark
                  ? const Color(0xFF262626)
                  : const Color(0xFFF5F5F5),
              valueColor: AlwaysStoppedAnimation<Color>(c),
            ),
          ),
          if (showInfo)
            label ??
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: size / 5,
                    fontWeight: FontWeight.w600,
                    color: AntdTokens.textColor(context),
                  ),
                ),
        ],
      ),
    );
  }
}
