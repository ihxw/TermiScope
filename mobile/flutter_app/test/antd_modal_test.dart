import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/widgets/antd/antd_button.dart';
import 'package:termiscope_mobile/widgets/antd/antd_modal.dart';

void main() {
  testWidgets('locks the confirm action while an async callback is running',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntdModal(
          okText: 'Save',
          cancelText: 'Cancel',
          onOk: () async {
            calls++;
            await completer.future;
          },
          child: const Text('Body'),
        ),
      ),
    ));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widgetList<AntdButton>(find.byType(AntdButton)).last.onPressed,
      isNull,
    );

    await tester.tap(find.text('Save'));
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('does not render an empty cancel action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AntdModal(
          okText: 'Close',
          cancelText: '',
          onOk: () {},
          child: const Text('Body'),
        ),
      ),
    ));

    expect(find.byType(AntdButton), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
