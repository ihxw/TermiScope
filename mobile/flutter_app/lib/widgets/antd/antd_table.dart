import 'package:flutter/material.dart';
import '../../app/antd_tokens.dart';
import 'antd_empty.dart';
import 'antd_spin.dart';

/// 表格列定义。
///
/// [title] 会渲染为 `Text`，如需更复杂表头可省略 title 并在 headerCell 中自建。
class AntdTableColumn<RowType> {
  const AntdTableColumn({
    this.title,
    required this.cell,
    this.width,
    this.minWidth,
    this.alignment = Alignment.centerLeft,
    this.headerCell,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  /// 列标题字符串。
  final String? title;

  /// 列宽，null 表示自适应（`IntrinsicColumnWidth`）。
  final double? width;
  final double? minWidth;
  final Alignment alignment;
  final EdgeInsetsGeometry padding;

  /// 自定义表头 cell；为 null 时自动用 [title] 渲染。
  final Widget Function(BuildContext)? headerCell;

  /// 单元格构建器。
  final Widget Function(BuildContext context, RowType row, int rowIndex) cell;
}

/// AntdTable 轻量复刻 ant-design-vue `a-table`。
///
/// 第一版能力：
/// - 表头 + 固定列宽
/// - 横向滚动（移动优先）
/// - 行选择列（自动在第一列增加复选框）
/// - loading / empty
/// - 可配行高与表头高
///
/// 暂未实现：列冻结、虚拟滚动、拖拽排序、单元格编辑。
class AntdTable<RowType> extends StatelessWidget {
  const AntdTable({
    super.key,
    required this.rowKey,
    required this.columns,
    this.data = const [],
    this.loading = false,
    this.selectedKeys,
    this.onSelectionChanged,
    this.headerHeight = AntdTokens.tableHeaderHeight,
    this.rowHeight = AntdTokens.tableRowHeight,
    this.headerBackground,
    this.headerTextStyle,
    this.rowBackground,
    this.hoverBackground,
    this.emptyWidget,
    this.onRowTap,
  });

  /// 行主键提取。
  final String Function(RowType row) rowKey;

  /// 列定义。
  final List<AntdTableColumn<RowType>> columns;
  final List<RowType> data;
  final bool loading;

  /// 当前选中行的 key 集合。
  final Set<String>? selectedKeys;
  final ValueChanged<Set<String>>? onSelectionChanged;

  final double headerHeight;
  final double rowHeight;
  final Color? headerBackground;
  final TextStyle? headerTextStyle;
  final Color? rowBackground;
  final Color? hoverBackground;
  final Widget? emptyWidget;
  final void Function(RowType row)? onRowTap;

  bool get _hasSelection =>
      selectedKeys != null && onSelectionChanged != null;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 300,
        child: AntdSpin(tip: '加载中...'),
      );
    }

    if (data.isEmpty) {
      return SizedBox(
        height: 300,
        child: emptyWidget ?? const AntdEmpty(),
      );
    }

    final totalWidth = _computeTotalWidth();
    final headerFg = AntdTokens.textColor(context);
    final headerBg = headerBackground ?? AntdTokens.containerSecondaryColor(context);
    final border = AntdTokens.borderSecondaryColor(context);
    final defaultHeaderStyle = TextStyle(
      fontSize: AntdTokens.fontSize,
      fontWeight: FontWeight.w600,
      color: headerFg,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ---- 表头 ----
        Container(
          height: headerHeight,
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(
              bottom: BorderSide(color: border),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Row(
                children: [
                  if (_hasSelection)
                    _buildHeaderCell(
                      '',
                      AntdTokens.tableHeaderHeight,
                      Alignment.center,
                      const EdgeInsets.symmetric(horizontal: 4),
                      defaultHeaderStyle,
                      context,
                    ),
                  for (final col in columns)
                    col.headerCell != null
                        ? _colContainer(col, col.headerCell!(context))
                        : _buildHeaderCell(
                            col.title ?? '',
                            col.width,
                            col.alignment,
                            col.padding,
                            defaultHeaderStyle,
                            context,
                          ),
                ],
              ),
            ),
          ),
        ),
        // ---- 数据行 ----
        Expanded(
          child: _ClipAntiAliasWrapper(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: ListView.builder(
                  itemCount: data.length,
                  itemExtent: rowHeight,
                  itemBuilder: (context, index) {
                    final row = data[index];
                    final key = rowKey(row);
                    final isSelected =
                        selectedKeys != null && selectedKeys!.contains(key);
                    final bg = isSelected
                        ? AntdTokens.primary.withAlpha(20)
                        : (_rowBg(context, index));

                    return _MouseRegionRow(
                      hoverBg: hoverBackground ??
                          AntdTokens.hoverColor(context),
                      rowBackground: bg,
                      child: InkWell(
                        onTap: onRowTap != null ? () => onRowTap!(row) : null,
                        child: Container(
                          height: rowHeight,
                          decoration: BoxDecoration(
                            color: bg,
                            border: Border(
                              bottom: BorderSide(color: border),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_hasSelection)
                                _buildCheckCell(key, isSelected, row, context),
                              for (final col in columns)
                                _colContainer(
                                  col,
                                  col.cell(context, row, index),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _rowBg(BuildContext context, int index) {
    if (rowBackground != null) return rowBackground!;
    return index.isEven
        ? AntdTokens.containerColor(context)
        : AntdTokens.containerSecondaryColor(context);
  }

  Widget _buildHeaderCell(
    String title,
    double? width,
    Alignment alignment,
    EdgeInsetsGeometry padding,
    TextStyle style,
    BuildContext context,
  ) {
    return Container(
      width: width,
      padding: padding,
      alignment: alignment,
      child: Text(
        title,
        style: headerTextStyle ?? style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _colContainer(
      AntdTableColumn<RowType> col, Widget child) {
    // 使用 container + alignment 确保单元格内容对齐
    return Container(
      width: col.width,
      padding: col.padding,
      alignment: col.alignment,
      child: child,
    );
  }

  Widget _buildCheckCell(
    String key,
    bool isSelected,
    RowType row,
    BuildContext context,
  ) {
    return SizedBox(
      width: 44,
      child: Checkbox(
        value: isSelected,
        activeColor: AntdTokens.primary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        onChanged: (v) {
          final newSet = Set<String>.from(selectedKeys!);
          if (v == true) {
            newSet.add(key);
          } else {
            newSet.remove(key);
          }
          onSelectionChanged?.call(newSet);
        },
      ),
    );
  }

  double _computeTotalWidth() {
    double w = _hasSelection ? 44 : 0;
    for (final col in columns) {
      w += col.width ?? 120;
    }
    return w;
  }
}

/// 简易 hover 行包装。
class _MouseRegionRow extends StatefulWidget {
  final Widget child;
  final Color hoverBg;
  final Color rowBackground;

  const _MouseRegionRow({
    required this.child,
    required this.hoverBg,
    required this.rowBackground,
  });

  @override
  State<_MouseRegionRow> createState() => _MouseRegionRowState();
}

class _MouseRegionRowState extends State<_MouseRegionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: _hover ? widget.hoverBg : widget.rowBackground,
        child: widget.child,
      ),
    );
  }
}

/// 确保横向滚动不溢出圆角区域。
class _ClipAntiAliasWrapper extends StatelessWidget {
  final Widget child;
  const _ClipAntiAliasWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    // Clip.hardEdge 解决 SingleChildScrollView 内子控件超出圆角的问题。
    return ClipRect(
      clipper: _BottomClip(),
      child: child,
    );
  }
}

class _BottomClip extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
