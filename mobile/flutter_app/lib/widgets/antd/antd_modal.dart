import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';
import 'antd_button.dart';

/// AntdModal 复刻 ant-design `a-modal` 的视觉骨架。
///
/// 在 Flutter 中通过 `showDialog` 或自行嵌入使用。提供：
/// - 标题栏 + 关闭按钮
/// - 主体内容区
/// - 底部 "取消 / 确定" 按钮（可自定义 [footer]）
typedef AntdModalOkCallback = FutureOr<void> Function();

class AntdModal extends StatefulWidget {
  const AntdModal({
    super.key,
    this.title,
    this.width = AntdTokens.modalWidth,
    this.padding,
    this.contentPadding,
    this.bodyMaxHeight,
    required this.child,
    this.footer,
    this.okText = '确定',
    this.cancelText = '取消',
    this.onOk,
    this.onCancel,
    this.confirmLoading = false,
    this.danger = false,
    this.showFooter = true,
  });

  final Widget? title;
  final double width;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;
  final double? bodyMaxHeight;
  final Widget child;

  /// 自定义底部，传入后忽略 [okText]/[cancelText]/[onOk]/[onCancel]。
  final List<Widget>? footer;

  final String okText;
  final String cancelText;
  final AntdModalOkCallback? onOk;
  final VoidCallback? onCancel;
  final bool confirmLoading;
  final bool danger;
  final bool showFooter;

  @override
  State<AntdModal> createState() => _AntdModalState();
}

class _AntdModalState extends State<AntdModal> {
  bool _confirmLoading = false;

  Future<void> _handleOk() async {
    if (_confirmLoading || widget.confirmLoading || widget.onOk == null) return;
    final result = widget.onOk!();
    if (result is! Future<void>) return;

    setState(() => _confirmLoading = true);
    try {
      await result;
    } finally {
      if (mounted) setState(() => _confirmLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AntdTokens.containerColor(context);
    final border = AntdTokens.borderSecondaryColor(context);
    final maxScreen = MediaQuery.of(context).size;
    final maxWidth = widget.width.clamp(0.0, maxScreen.width - 24);
    final maxHeight = widget.bodyMaxHeight ?? (maxScreen.height - 120);
    final loading = widget.confirmLoading || _confirmLoading;

    final actions = widget.footer ??
        [
          if (widget.cancelText.trim().isNotEmpty)
            AntdButton(
              onPressed:
                  widget.onCancel ?? () => Navigator.of(context).maybePop(),
              child: Text(widget.cancelText),
            ),
          AntdButton(
            type: AntdButtonType.primary,
            danger: widget.danger,
            loading: loading,
            onPressed: widget.onOk == null || loading ? null : _handleOk,
            child: Text(widget.okText),
          ),
        ];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: maxWidth,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AntdTokens.radiusLG),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AntdTokens.paddingMD,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontSize: AntdTokens.fontSizeLG,
                          fontWeight: FontWeight.w600,
                          color: AntdTokens.textColor(context),
                        ),
                        child: widget.title!,
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(2),
                      onTap: widget.onCancel ??
                          () => Navigator.of(context).maybePop(),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: AntdTokens.secondaryTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: widget.contentPadding ??
                      const EdgeInsets.symmetric(
                        horizontal: AntdTokens.paddingMD,
                        vertical: AntdTokens.paddingMD,
                      ),
                  child: widget.child,
                ),
              ),
            ),
            if (widget.showFooter)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AntdTokens.paddingMD,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
