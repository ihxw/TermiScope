import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/widgets/antd/antd_toolbar.dart';

void main() {
  Future<void> pumpToolbar(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 300);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AntdToolbar(
                leading: [Text('Leading', key: Key('toolbar-leading'))],
                trailing: [Text('Trailing', key: Key('toolbar-trailing'))],
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('fills the available width and keeps actions at both edges',
      (tester) async {
    await pumpToolbar(tester, 1600);

    expect(tester.getSize(find.byType(AntdToolbar)).width, 1600);
    expect(tester.getTopLeft(find.byKey(const Key('toolbar-leading'))).dx,
        lessThan(24));
    expect(tester.getTopRight(find.byKey(const Key('toolbar-trailing'))).dx,
        greaterThan(1570));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains full width without overflow on a narrow viewport',
      (tester) async {
    await pumpToolbar(tester, 390);

    expect(tester.getSize(find.byType(AntdToolbar)).width, 390);
    expect(tester.takeException(), isNull);
  });
}
