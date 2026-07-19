import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_button.dart';

/// 冲突解决策略。
enum AntdConflictStrategy { overwrite, skip, rename, keepBoth }

/// AntdConflictModal 文件冲突弹窗。
///
/// 当上传/移动文件时遇到同名文件，弹出此窗口供用户选择：
/// - 覆盖 (overwrite)
/// - 跳过 (skip)
/// - 重命名 (rename)
/// - 保留两者 (keepBoth)
///
/// 可通过 [applyToAll] 将策略应用到所有后续冲突。
class AntdConflictModal extends StatefulWidget {
  const AntdConflictModal({
    super.key,
    required this.fileName,
    this.existingInfo,
    this.newInfo,
    required this.onResolve,
  });

  final String fileName;
  final String? existingInfo; // e.g. "12.5 MB • 2024-01-15"
  final String? newInfo; // e.g. "12.3 MB • 2024-01-20"
  final void Function(AntdConflictStrategy strategy, bool applyToAll) onResolve;

  @override
  State<AntdConflictModal> createState() => _AntdConflictModalState();
}

class _AntdConflictModalState extends State<AntdConflictModal> {
  bool _applyToAll = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          color: AntdTokens.containerColor(context),
          borderRadius: BorderRadius.circular(AntdTokens.radiusLG),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: AntdTokens.borderSecondaryColor(context)),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      size: 20, color: AntdTokens.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '\u6587\u4ef6\u5df2\u5b58\u5728',
                      style: TextStyle(
                        fontSize: AntdTokens.fontSizeLG,
                        fontWeight: FontWeight.w600,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      fontWeight: FontWeight.w600,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.existingInfo != null)
                    Text(
                      '\u5df2\u6709: ${widget.existingInfo}',
                      style: TextStyle(
                        fontSize: AntdTokens.fontSizeSM,
                        color: AntdTokens.secondaryTextColor(context),
                      ),
                    ),
                  if (widget.newInfo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '\u65b0\u7684: ${widget.newInfo}',
                      style: TextStyle(
                        fontSize: AntdTokens.fontSizeSM,
                        color: AntdTokens.secondaryTextColor(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '\u8bf7\u9009\u62e9\u5904\u7406\u65b9\u5f0f\uff1a',
                    style: TextStyle(
                      fontSize: AntdTokens.fontSize,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Strategy buttons
                  _buildOption(
                    AntdConflictStrategy.overwrite,
                    '\u8986\u76d6',
                    Icons.file_copy,
                    '\u4f7f\u7528\u65b0\u6587\u4ef6\u66ff\u6362\u65e7\u6587\u4ef6',
                  ),
                  _buildOption(
                    AntdConflictStrategy.skip,
                    '\u8df3\u8fc7',
                    Icons.skip_next,
                    '\u4fdd\u7559\u73b0\u6709\u6587\u4ef6\uff0c\u4e0d\u4e0a\u4f20\u6b64\u6587\u4ef6',
                  ),
                  _buildOption(
                    AntdConflictStrategy.rename,
                    '\u91cd\u547d\u540d',
                    Icons.drive_file_rename_outline,
                    '\u4fdd\u7559\u4e24\u4e2a\u6587\u4ef6\uff0c\u65b0\u6587\u4ef6\u81ea\u52a8\u6dfb\u52a0\u540e\u7f00',
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: AntdTokens.borderSecondaryColor(context)),
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _applyToAll = !_applyToAll),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: Checkbox(
                            value: _applyToAll,
                            activeColor: AntdTokens.primary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) =>
                                setState(() => _applyToAll = v == true),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '\u5e94\u7528\u5230\u6240\u6709',
                          style: TextStyle(
                            fontSize: AntdTokens.fontSizeSM,
                            color: AntdTokens.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  AntdButton(
                    onPressed: () {
                      widget.onResolve(
                          AntdConflictStrategy.skip, _applyToAll);
                    },
                    child: const Text('\u8df3\u8fc7'),
                  ),
                  const SizedBox(width: 8),
                  AntdButton(
                    type: AntdButtonType.primary,
                    onPressed: () {
                      widget.onResolve(
                          AntdConflictStrategy.overwrite, _applyToAll);
                    },
                    child: const Text('\u8986\u76d6'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    AntdConflictStrategy strategy,
    String title,
    IconData icon,
    String desc,
  ) {
    final border = AntdTokens.borderSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(AntdTokens.radius),
        onTap: () => widget.onResolve(strategy, _applyToAll),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(AntdTokens.radius),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AntdTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AntdTokens.fontSize,
                        fontWeight: FontWeight.w600,
                        color: AntdTokens.textColor(context),
                      ),
                    ),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: AntdTokens.fontSizeSM,
                        color: AntdTokens.secondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
