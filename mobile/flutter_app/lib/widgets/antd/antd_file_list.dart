import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_action_menu.dart';
import 'antd_empty.dart';

class AntdFileEntry {
  const AntdFileEntry({
    required this.name,
    this.isDir = false,
    this.size,
    this.modifiedTime,
    this.icon,
    this.extra,
  });
  final String name;
  final bool isDir;
  final int? size;
  final String? modifiedTime;
  final IconData? icon;
  final dynamic extra;
}

class AntdFileList extends StatelessWidget {
  const AntdFileList({
    super.key,
    required this.files,
    this.onDirTap,
    this.onFileTap,
    this.actions,
    this.onAction,
    this.loading = false,
    this.emptyText,
    this.selectedNames = const {},
    this.onSelectionChanged,
  });

  final List<AntdFileEntry> files;
  final ValueChanged<AntdFileEntry>? onDirTap;
  final ValueChanged<AntdFileEntry>? onFileTap;
  final List<AntdActionMenuItem> Function(AntdFileEntry)? actions;
  final void Function(String key, AntdFileEntry entry)? onAction;
  final bool loading;
  final String? emptyText;
  final Set<String> selectedNames;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (files.isEmpty) {
      return Center(
          child:
              AntdEmpty(description: emptyText ?? '\u6682\u65e0\u6587\u4ef6'));
    }
    final border = AntdTokens.borderSecondaryColor(context);
    final sec = AntdTokens.secondaryTextColor(context);
    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (_, __) => Container(height: 1, color: border),
      itemBuilder: (ctx, i) {
        final e = files[i];
        return InkWell(
          onTap: () => e.isDir ? onDirTap?.call(e) : onFileTap?.call(e),
          child: Container(
            height: AntdTokens.tableRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              if (onSelectionChanged != null) ...[
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: selectedNames.contains(e.name),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: AntdTokens.primary,
                    onChanged: (checked) {
                      final next = Set<String>.from(selectedNames);
                      checked == true ? next.add(e.name) : next.remove(e.name);
                      onSelectionChanged!(next);
                    },
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Icon(e.icon ?? (e.isDir ? Icons.folder : Icons.insert_drive_file),
                  size: 18,
                  color: e.isDir
                      ? const Color(0xFFFAAD14)
                      : const Color(0xFF8C8C8C)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(e.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: AntdTokens.fontSize,
                          fontWeight:
                              e.isDir ? FontWeight.w600 : FontWeight.w400,
                          color: AntdTokens.textColor(context)))),
              if (e.size != null) ...[
                const SizedBox(width: 12),
                Text(_fmt(e.size!),
                    style:
                        TextStyle(fontSize: AntdTokens.fontSizeSM, color: sec)),
              ],
              if (e.modifiedTime != null) ...[
                const SizedBox(width: 12),
                Text(e.modifiedTime!,
                    style:
                        TextStyle(fontSize: AntdTokens.fontSizeSM, color: sec)),
              ],
              if (actions != null && onAction != null) ...[
                const SizedBox(width: 4),
                AntdActionMenu(
                    items: actions!(e), onAction: (k) => onAction!.call(k, e)),
              ],
            ]),
          ),
        );
      },
    );
  }

  String _fmt(int b) {
    if (b <= 0) return '0 B';
    const s = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double sz = b.toDouble();
    while (sz >= 1024 && i < s.length - 1) {
      sz /= 1024;
      i++;
    }
    return '${sz.toStringAsFixed(1)} ${s[i]}';
  }
}
