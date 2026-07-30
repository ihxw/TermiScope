import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';
import 'antd_button.dart';

/// AntdSelectOption 表示 [AntdSelect] 的一个选项。
class AntdSelectOption<T> {
  const AntdSelectOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// AntdSelect 复刻 ant-design `a-select` 的下拉选择控件。
///
/// 视觉与 [AntdInput] 对齐：高度 `controlHeight` (32) / `controlHeightLG` (40)，
/// 1px 边框，hover/focus 主色边框。
///
/// 弹出层使用 [showMenu]，菜单项颜色与 [AntdDropdown] 一致。
class AntdSelect<T> extends StatefulWidget {
  const AntdSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.size = AntdSize.middle,
    this.disabled = false,
    this.error = false,
    this.allowClear = false,
  });

  final T? value;
  final List<AntdSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String? placeholder;
  final AntdSize size;
  final bool disabled;
  final bool error;
  final bool allowClear;

  @override
  State<AntdSelect<T>> createState() => _AntdSelectState<T>();
}

class _AntdSelectState<T> extends State<AntdSelect<T>> {
  bool _hover = false;

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

  Future<void> _open() async {
    if (widget.disabled) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final origin = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final size = renderBox.size;
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + size.height + 4,
      overlay.size.width - origin.dx - size.width,
      overlay.size.height,
    );

    final selected = await showMenu<T>(
      context: context,
      position: position,
      color: AntdTokens.containerColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AntdTokens.radiusLG),
        side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
      ),
      constraints: BoxConstraints(minWidth: size.width, maxWidth: size.width),
      items: widget.options
          .map(
            (opt) => PopupMenuItem<T>(
              value: opt.value,
              height: 32,
              child: Row(
                children: [
                  if (opt.icon != null) ...[
                    Icon(opt.icon, size: 14),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      opt.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AntdTokens.fontSize,
                        color: opt.value == widget.value
                            ? AntdTokens.primary
                            : AntdTokens.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );

    if (selected != null) widget.onChanged(selected);
  }

  String _labelOf(T? value) {
    final option = widget.options.firstWhere(
      (o) => o.value == value,
      orElse: () => AntdSelectOption<T>(value: value as T, label: ''),
    );
    return option.label;
  }

  IconData? _iconOf(T? value) {
    for (final o in widget.options) {
      if (o.value == value) return o.icon;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null && _labelOf(widget.value).isNotEmpty;
    final label = hasValue ? _labelOf(widget.value) : (widget.placeholder ?? '');

    Color borderColor;
    if (widget.error) {
      borderColor = AntdTokens.error;
    } else if (_hover && !widget.disabled) {
      borderColor = AntdTokens.primary;
    } else {
      borderColor = AntdTokens.borderColor(context);
    }

    final fill = widget.disabled
        ? (AntdTokens.isDark(context)
            ? const Color(0xFF262626)
            : const Color(0xFFF5F5F5))
        : AntdTokens.containerColor(context);

    final textColor = !hasValue
        ? AntdTokens.secondaryTextColor(context)
        : (widget.disabled
            ? AntdTokens.disabledTextColor(context)
            : AntdTokens.textColor(context));

    final icon = _iconOf(widget.value);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(AntdTokens.radius),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: textColor),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AntdTokens.fontSize,
                    color: textColor,
                  ),
                ),
              ),
              if (widget.allowClear &&
                  hasValue &&
                  !widget.disabled)
                GestureDetector(
                  onTap: () => widget.onChanged(null),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.cancel,
                      size: 14,
                      color: AntdTokens.secondaryTextColor(context),
                    ),
                  ),
                ),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: AntdTokens.secondaryTextColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
