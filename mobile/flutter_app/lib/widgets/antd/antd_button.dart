import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdButton 按钮类型，对齐 ant-design 的 type 属性。
enum AntdButtonType { primary, defaultType, dashed, text, link }

/// AntdButton 尺寸。
enum AntdSize { small, middle, large }

/// 复刻 ant-design-vue 的按钮样式与交互。
///
/// 支持：
/// - `type`：primary / default / dashed / text / link
/// - `size`：small(24) / middle(32) / large(40)
/// - `icon`：图标
/// - `loading`：加载态
/// - `danger`：危险态，将主色替换为错误色
/// - `block`：撑满父级宽度
class AntdButton extends StatefulWidget {
  const AntdButton({
    super.key,
    required this.onPressed,
    this.type = AntdButtonType.defaultType,
    this.size = AntdSize.middle,
    this.icon,
    this.loading = false,
    this.danger = false,
    this.block = false,
    this.child,
  });

  final VoidCallback? onPressed;
  final AntdButtonType type;
  final AntdSize size;
  final IconData? icon;
  final bool loading;
  final bool danger;
  final bool block;
  final Widget? child;

  @override
  State<AntdButton> createState() => _AntdButtonState();
}

class _AntdButtonState extends State<AntdButton> {
  bool _hover = false;
  bool _pressed = false;

  double get _height {
    switch (widget.size) {
      case AntdSize.small:
        return AntdTokens.controlHeightSM;
      case AntdSize.large:
        return AntdTokens.controlHeightLG;
      case AntdSize.middle:
        return AntdTokens.controlHeight;
    }
  }

  double get _fontSize {
    switch (widget.size) {
      case AntdSize.small:
        return AntdTokens.fontSize;
      case AntdSize.large:
        return AntdTokens.fontSizeLG;
      case AntdSize.middle:
        return AntdTokens.fontSize;
    }
  }

  EdgeInsets get _padding {
    switch (widget.size) {
      case AntdSize.small:
        return const EdgeInsets.symmetric(horizontal: 7);
      case AntdSize.large:
        return const EdgeInsets.symmetric(horizontal: 15);
      case AntdSize.middle:
        return const EdgeInsets.symmetric(horizontal: 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    final isDark = AntdTokens.isDark(context);
    final mainColor =
        widget.danger ? AntdTokens.error : AntdTokens.primary;

    Color bg;
    Color fg;
    Color border;
    BorderStyle borderStyle = BorderStyle.solid;

    switch (widget.type) {
      case AntdButtonType.primary:
        bg = _hover && !disabled
            ? AntdTokens.primaryHover
            : (_pressed && !disabled ? AntdTokens.primaryActive : mainColor);
        fg = Colors.white;
        border = bg;
        if (disabled) {
          bg = isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5);
          fg = AntdTokens.disabledTextColor(context);
          border = AntdTokens.borderColor(context);
        }
        break;
      case AntdButtonType.defaultType:
        bg = AntdTokens.containerColor(context);
        fg = widget.danger ? AntdTokens.error : AntdTokens.textColor(context);
        border = widget.danger
            ? AntdTokens.error
            : AntdTokens.borderColor(context);
        if (_hover && !disabled) {
          fg = mainColor;
          border = mainColor;
        }
        if (disabled) {
          fg = AntdTokens.disabledTextColor(context);
          border = AntdTokens.borderColor(context);
          bg = isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5);
        }
        break;
      case AntdButtonType.dashed:
        bg = AntdTokens.containerColor(context);
        fg = widget.danger ? AntdTokens.error : AntdTokens.textColor(context);
        border = widget.danger
            ? AntdTokens.error
            : AntdTokens.borderColor(context);
        borderStyle = BorderStyle.solid; // Flutter 不直接支持 dashed
        if (_hover && !disabled) {
          fg = mainColor;
          border = mainColor;
        }
        if (disabled) {
          fg = AntdTokens.disabledTextColor(context);
          border = AntdTokens.borderColor(context);
        }
        break;
      case AntdButtonType.text:
        bg = _hover && !disabled
            ? AntdTokens.hoverColor(context)
            : Colors.transparent;
        fg = widget.danger ? AntdTokens.error : AntdTokens.textColor(context);
        border = Colors.transparent;
        if (disabled) fg = AntdTokens.disabledTextColor(context);
        break;
      case AntdButtonType.link:
        bg = Colors.transparent;
        fg = _hover && !disabled
            ? (widget.danger
                ? AntdTokens.error
                : AntdTokens.primaryHover)
            : (widget.danger ? AntdTokens.error : AntdTokens.primary);
        border = Colors.transparent;
        if (disabled) fg = AntdTokens.disabledTextColor(context);
        break;
    }

    final textStyle = TextStyle(
      color: fg,
      fontSize: _fontSize,
      fontWeight: FontWeight.w400,
      height: 1.1,
    );

    Widget content;
    if (widget.loading) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: _fontSize,
            height: _fontSize,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          ),
          if (widget.child != null) ...[
            const SizedBox(width: AntdTokens.paddingSM),
            DefaultTextStyle(style: textStyle, child: widget.child!),
          ],
        ],
      );
    } else if (widget.icon != null && widget.child != null) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: _fontSize, color: fg),
          const SizedBox(width: 6),
          DefaultTextStyle(style: textStyle, child: widget.child!),
        ],
      );
    } else if (widget.icon != null) {
      content = Icon(widget.icon, size: _fontSize, color: fg);
    } else {
      content = DefaultTextStyle(
        style: textStyle,
        textAlign: TextAlign.center,
        child: widget.child ?? const SizedBox.shrink(),
      );
    }

    final button = MouseRegion(
      cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapCancel: disabled ? null : () => setState(() => _pressed = false),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _height,
          padding: _padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, style: borderStyle, width: 1),
            borderRadius: BorderRadius.circular(AntdTokens.radius),
          ),
          child: content,
        ),
      ),
    );

    if (widget.block) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
