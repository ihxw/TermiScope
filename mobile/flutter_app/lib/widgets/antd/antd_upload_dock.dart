import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_button.dart';
import 'antd_progress.dart';

/// 上传任务条目。
class AntdUploadTask {
  const AntdUploadTask({
    required this.id,
    required this.name,
    required this.totalBytes,
    this.uploadedBytes = 0,
    this.status = AntdUploadStatus.uploading,
  });

  final String id;
  final String name;
  final int totalBytes;
  final int uploadedBytes;
  final AntdUploadStatus status;

  double get progress =>
      totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0, 1).toDouble() : 0;

  AntdUploadTask copyWith({
    int? totalBytes,
    int? uploadedBytes,
    AntdUploadStatus? status,
  }) =>
      AntdUploadTask(
        id: id,
        name: name,
        totalBytes: totalBytes ?? this.totalBytes,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        status: status ?? this.status,
      );
}

/// 上传状态。
enum AntdUploadStatus { uploading, success, failed, cancelled }

/// AntdUploadProgressDock 上传进度条底栏。
///
/// 常驻于页面底部，展示正在进行的上传任务列表。
/// 可折叠/展开，每项显示文件名、进度条、取消按钮。
class AntdUploadProgressDock extends StatelessWidget {
  const AntdUploadProgressDock({
    super.key,
    required this.tasks,
    this.onCancel,
    this.onRetry,
    this.onClear,
    this.expanded = false,
    this.title,
    this.cancelText = '取消',
    this.retryText = '重试',
    this.clearText = '清除',
  });

  final List<AntdUploadTask> tasks;
  final ValueChanged<String>? onCancel;
  final ValueChanged<String>? onRetry;
  final VoidCallback? onClear;
  final bool expanded;
  final String? title;
  final String cancelText;
  final String retryText;
  final String clearText;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    final bg = AntdTokens.containerColor(context);
    final border = AntdTokens.borderSecondaryColor(context);
    final activeCount =
        tasks.where((t) => t.status == AntdUploadStatus.uploading).length;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 14, color: AntdTokens.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title ?? '\u4e0a\u4f20\u4e2d ($activeCount)',
                    style: TextStyle(
                      fontSize: AntdTokens.fontSizeSM,
                      fontWeight: FontWeight.w600,
                      color: AntdTokens.textColor(context),
                    ),
                  ),
                ),
                if (onClear != null)
                  AntdButton(
                    type: AntdButtonType.link,
                    size: AntdSize.small,
                    onPressed: onClear,
                    child: Text(clearText),
                  ),
              ],
            ),
          ),
          // Task list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tasks.length,
              separatorBuilder: (_, __) => Container(height: 1, color: border),
              itemBuilder: (_, i) {
                final task = tasks[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      _statusIcon(task.status, context),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AntdTokens.fontSizeSM,
                                color: AntdTokens.textColor(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            AntdProgress(
                              percent: task.progress * 100,
                              strokeWidth: 3,
                              showInfo: false,
                              color: task.status == AntdUploadStatus.failed
                                  ? AntdTokens.error
                                  : task.status == AntdUploadStatus.success
                                      ? AntdTokens.success
                                      : AntdTokens.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(task.progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: AntdTokens.fontSizeSM,
                          color: AntdTokens.secondaryTextColor(context),
                        ),
                      ),
                      if (task.status == AntdUploadStatus.uploading) ...[
                        const SizedBox(width: 4),
                        AntdButton(
                          type: AntdButtonType.link,
                          size: AntdSize.small,
                          onPressed: () => onCancel?.call(task.id),
                          child: Text(cancelText),
                        ),
                      ] else if (task.status == AntdUploadStatus.failed ||
                          task.status == AntdUploadStatus.cancelled) ...[
                        const SizedBox(width: 4),
                        AntdButton(
                          type: AntdButtonType.link,
                          size: AntdSize.small,
                          icon: Icons.refresh,
                          onPressed: onRetry == null
                              ? null
                              : () => onRetry!.call(task.id),
                          child: Text(retryText),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(AntdUploadStatus status, BuildContext context) {
    return switch (status) {
      AntdUploadStatus.success =>
        const Icon(Icons.check_circle, size: 14, color: AntdTokens.success),
      AntdUploadStatus.failed =>
        const Icon(Icons.error, size: 14, color: AntdTokens.error),
      AntdUploadStatus.cancelled => Icon(Icons.cancel,
          size: 14, color: AntdTokens.secondaryTextColor(context)),
      AntdUploadStatus.uploading => SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: const AlwaysStoppedAnimation<Color>(AntdTokens.primary),
          ),
        ),
    };
  }
}
