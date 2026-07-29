import 'package:flutter/material.dart';

import '../../app/antd_tokens.dart';

/// AntdFormItem 表单项，包含上方 label、必填星号、下方帮助/错误文案。
class AntdFormItem extends StatelessWidget {
  const AntdFormItem({
    super.key,
    this.label,
    this.required = false,
    this.help,
    this.error,
    this.extra,
    required this.child,
    this.labelWidth,
  });

  final String? label;
  final bool required;

  /// 普通帮助文本。
  final String? help;

  /// 错误文本，传入后会以 [AntdTokens.error] 颜色展示并接管 [help]。
  final String? error;

  /// 额外尾部部件（与 label 同一行右侧），常用于"忘记密码"链接。
  final Widget? extra;
  final Widget child;

  /// 暂未使用，预留水平 label 模式。
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.isNotEmpty;
    final showError = error != null && error!.isNotEmpty;
    final showHelp = !showError && help != null && help!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                if (required)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Text(
                      '*',
                      style: TextStyle(
                        color: AntdTokens.error,
                        fontSize: AntdTokens.fontSize,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    label!,
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                ),
                if (extra != null) extra!,
              ],
            ),
          ),
        child,
        if (showError)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              style: const TextStyle(
                fontSize: AntdTokens.fontSizeSM,
                color: AntdTokens.error,
              ),
            ),
          ),
        if (showHelp)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              help!,
              style: TextStyle(
                fontSize: AntdTokens.fontSizeSM,
                color: AntdTokens.secondaryTextColor(context),
              ),
            ),
          ),
      ],
    );
  }
}
