import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_button.dart';

/// AntdPagination 复刻 ant-design `a-pagination` 简易版分页器。
///
/// 支持：
/// - 上/下页按钮
/// - 当前页/总页数显示
/// - 每页条数切换
/// - `simple` 模式仅显示 "第 X/Y 页" 无下拉
class AntdPagination extends StatelessWidget {
  const AntdPagination({
    super.key,
    required this.current,
    required this.total,
    this.pageSize = 20,
    this.pageSizeOptions = const [10, 20, 50, 100],
    this.onChange,
    this.onPageSizeChange,
    this.simple = false,
    this.showTotal = false,
    this.position = AntdPaginationPosition.right,
  });

  /// 当前页码（1-based）。
  final int current;

  /// 总条目数。
  final int total;

  /// 每页条数。
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onChange;
  final ValueChanged<int>? onPageSizeChange;
  final bool simple;
  final bool showTotal;
  final AntdPaginationPosition position;

  int get _totalPages => (total / pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalPages;
    if (totalPages <= 0) return const SizedBox.shrink();

    final secondary = AntdTokens.secondaryTextColor(context);

    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AntdButton(
          size: AntdSize.small,
          onPressed: current > 1 ? () => onChange?.call(current - 1) : null,
          child: const Text('←'),
        ),
        const SizedBox(width: 8),
        Text(
          '$current / $totalPages',
          style: TextStyle(fontSize: AntdTokens.fontSize, color: secondary),
        ),
        const SizedBox(width: 8),
        AntdButton(
          size: AntdSize.small,
          onPressed:
              current < totalPages ? () => onChange?.call(current + 1) : null,
          child: const Text('→'),
        ),
      ],
    );

    if (simple) {
      return Align(
        alignment: position == AntdPaginationPosition.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: nav,
      );
    }

    // 含总数+每页条数
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: position == AntdPaginationPosition.right
            ? MainAxisAlignment.end
            : MainAxisAlignment.spaceBetween,
        children: [
          if (showTotal)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '共 $total 条',
                style:
                    TextStyle(fontSize: AntdTokens.fontSize, color: secondary),
              ),
            ),
          // Page size selector (simple inline)
          if (pageSizeOptions.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _PageSizeSelector(
                value: pageSize,
                options: pageSizeOptions,
                onChanged: onPageSizeChange,
              ),
            ),
          nav,
        ],
      ),
    );
  }
}

class _PageSizeSelector extends StatelessWidget {
  final int value;
  final List<int> options;
  final ValueChanged<int>? onChanged;

  const _PageSizeSelector({
    required this.value,
    required this.options,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value 条/页',
          style: TextStyle(
            fontSize: AntdTokens.fontSizeSM,
            color: AntdTokens.secondaryTextColor(context),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<int>(
          padding: EdgeInsets.zero,
          tooltip: '',
          color: AntdTokens.containerColor(context),
          offset: const Offset(0, 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: AntdTokens.borderSecondaryColor(context)),
          ),
          onSelected: onChanged,
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: AntdTokens.secondaryTextColor(context),
          ),
          itemBuilder: (ctx) => options
              .map((s) => PopupMenuItem<int>(
                    value: s,
                    height: 28,
                    child: Text(
                      '$s 条/页',
                      style: TextStyle(
                        fontSize: AntdTokens.fontSizeSM,
                        color: s == value
                            ? AntdTokens.primary
                            : AntdTokens.textColor(context),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

enum AntdPaginationPosition { left, right }
