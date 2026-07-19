import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/widgets/antd/antd_table.dart';

void main() {
  testWidgets('header checkbox selects only selectable rows', (tester) async {
    var selected = <String>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AntdTable<int>(
              rowKey: (row) => '$row',
              data: const [1, 2, 3],
              columns: [
                AntdTableColumn<int>(
                  title: 'Value',
                  width: 160,
                  cell: (_, row, __) => Text('$row'),
                ),
              ],
              selectedKeys: selected,
              selectable: (row) => row != 2,
              onSelectionChanged: (keys) {
                setState(() => selected = keys);
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    expect(selected, {'1', '3'});
    expect(
        tester.widget<Checkbox>(find.byType(Checkbox).at(2)).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps header and body aligned while scrolling horizontally',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 500);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AntdTable<int>(
            rowKey: (row) => '$row',
            data: const [1],
            columns: [
              AntdTableColumn<int>(
                width: 600,
                headerCell: (_) => const Align(
                  alignment: Alignment.centerRight,
                  child: Text('Header end', key: Key('header-end')),
                ),
                cell: (_, row, __) => const Align(
                  alignment: Alignment.centerRight,
                  child: Text('Body end', key: Key('body-end')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final bodyScroll = find.byType(SingleChildScrollView).last;
    await tester.drag(bodyScroll, const Offset(-220, 0));
    await tester.pump();

    final headerRight =
        tester.getTopRight(find.byKey(const Key('header-end'))).dx;
    final bodyRight = tester.getTopRight(find.byKey(const Key('body-end'))).dx;
    expect((headerRight - bodyRight).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
