import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdSwitch 复刻 ant-design `a-switch` 的开关。
///
/// - 高度默认 22（与 ant-design 一致），传入 `size = AntdSwitchSize.small` 后高度为 16
/// - 关闭态背景为浅灰，开启态使用 `colorPrimary`
/// - 圆角胶囊
class AntdSwitch extends StatelessWidget {
  const AntdSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = AntdSwitchSize.middle,
    this.disabled = false,
    this.color,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final AntdSwitchSize size;
  final bool disabled;

  /// 自定义开启色，默认 [AntdTokens.primary]。
  final Color? color;

  double get _height => size == AntdSwitchSize.small ? 16 : 22;
  double get _width => size == AntdSwitchSize.small ? 28 : 44;
  double get _thumb => size == AntdSwitchSize.small ? 12 : 18;

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AntdTokens.primary;
    final inactiveColor = AntdTokens.isDark(context)
        ? const Color(0xFF434343)
        : const Color(0xFFBFBFBF);
    final bg = disabled
        ? (value ? activeColor.withAlpha(120) : inactiveColor.withAlpha(120))
        : (value ? activeColor : inactiveColor);

    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled || onChanged == null
            ? null
            : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                left: value ? _width - _thumb - 2 : 2,
                top: (_height - _thumb) / 2,
                child: Container(
                  width: _thumb,
                  height: _thumb,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(_thumb / 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum AntdSwitchSize { small, middle }
