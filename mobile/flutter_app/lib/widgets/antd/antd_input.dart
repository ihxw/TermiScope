import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/antd_tokens.dart';
import 'antd_button.dart';

/// AntdInput 文本输入框，复刻 ant-design-vue `a-input` 视觉。
///
/// - 高度对齐 `controlHeight`（默认 32）
/// - 边框、focus 边框、placeholder 颜色与 Web 一致
/// - 支持 `prefix` / `suffix`、`prefixIcon` / `suffixIcon`
/// - 支持错误态、禁用态、密码模式（带显隐切换）
class AntdInput extends StatefulWidget {
  const AntdInput({
    super.key,
    this.controller,
    this.placeholder,
    this.obscureText = false,
    this.allowToggleObscure = false,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.error = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.size = AntdSize.middle,
    this.autofocus = false,
    this.focusNode,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final bool obscureText;

  /// 当为 true 时尾部显示眼睛图标用于切换显隐密码。
  final bool allowToggleObscure;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool error;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final AntdSize size;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  @override
  State<AntdInput> createState() => _AntdInputState();
}

class _AntdInputState extends State<AntdInput> {
  late FocusNode _focusNode;
  bool _focused = false;
  bool _hover = false;
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant AntdInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

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
      case AntdSize.middle:
        return AntdTokens.fontSize;
      case AntdSize.large:
        return AntdTokens.fontSizeLG;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    final disabled = !widget.enabled;
    final isMultiline = (widget.maxLines ?? 1) > 1;

    Color borderColor;
    if (widget.error) {
      borderColor = AntdTokens.error;
    } else if (_focused) {
      borderColor = AntdTokens.primary;
    } else if (_hover && !disabled) {
      borderColor = AntdTokens.primary;
    } else {
      borderColor = AntdTokens.borderColor(context);
    }

    final fillColor = disabled
        ? (isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5))
        : AntdTokens.containerColor(context);

    final textColor = disabled
        ? AntdTokens.disabledTextColor(context)
        : AntdTokens.textColor(context);

    Widget? prefixWidget;
    if (widget.prefix != null) {
      prefixWidget = widget.prefix;
    } else if (widget.prefixIcon != null) {
      prefixWidget = Icon(
        widget.prefixIcon,
        size: 16,
        color: AntdTokens.secondaryTextColor(context),
      );
    }

    Widget? suffixWidget;
    if (widget.allowToggleObscure) {
      suffixWidget = GestureDetector(
        onTap: disabled ? null : () => setState(() => _obscured = !_obscured),
        child: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 16,
          color: AntdTokens.secondaryTextColor(context),
        ),
      );
    } else if (widget.suffix != null) {
      suffixWidget = widget.suffix;
    } else if (widget.suffixIcon != null) {
      suffixWidget = Icon(
        widget.suffixIcon,
        size: 16,
        color: AntdTokens.secondaryTextColor(context),
      );
    }

    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: _obscured,
      maxLines: _obscured ? 1 : widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      cursorColor: AntdTokens.primary,
      style: TextStyle(fontSize: _fontSize, color: textColor),
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        hintText: widget.placeholder,
        hintStyle: TextStyle(
          color: AntdTokens.secondaryTextColor(context),
          fontSize: _fontSize,
        ),
      ),
    );

    final padding = EdgeInsets.symmetric(
      horizontal: 11,
      vertical: isMultiline ? 8 : 0,
    );

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: isMultiline
            ? BoxConstraints(minHeight: _height)
            : BoxConstraints(minHeight: _height, maxHeight: _height),
        padding: padding,
        decoration: BoxDecoration(
          color: fillColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AntdTokens.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (prefixWidget != null) ...[
              prefixWidget,
              const SizedBox(width: 6),
            ],
            Expanded(child: field),
            if (suffixWidget != null) ...[
              const SizedBox(width: 6),
              suffixWidget,
            ],
          ],
        ),
      ),
    );
  }
}

/// 密码输入框便捷类，等价于 `AntdInput(obscureText: true, allowToggleObscure: true)`。
class AntdPasswordInput extends StatelessWidget {
  const AntdPasswordInput({
    super.key,
    this.controller,
    this.placeholder,
    this.prefixIcon,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.error = false,
    this.size = AntdSize.middle,
    this.focusNode,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool error;
  final AntdSize size;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return AntdInput(
      controller: controller,
      placeholder: placeholder,
      prefixIcon: prefixIcon,
      obscureText: true,
      allowToggleObscure: true,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      error: error,
      size: size,
      focusNode: focusNode,
      textInputAction: textInputAction,
    );
  }
}

/// 多行文本框，等价于 `AntdInput` 的 multi-line 版本。
class AntdTextArea extends StatelessWidget {
  const AntdTextArea({
    super.key,
    this.controller,
    this.placeholder,
    this.minLines = 3,
    this.maxLines = 6,
    this.onChanged,
    this.enabled = true,
    this.error = false,
  });

  final TextEditingController? controller;
  final String? placeholder;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return AntdInput(
      controller: controller,
      placeholder: placeholder,
      onChanged: onChanged,
      enabled: enabled,
      error: error,
      minLines: minLines,
      maxLines: maxLines,
    );
  }
}
