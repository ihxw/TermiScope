import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:termiscope_mobile/models/models.dart';
import 'package:termiscope_mobile/providers/app_state.dart';
import 'package:termiscope_mobile/screens/file_transfer_screen.dart';
import 'package:termiscope_mobile/widgets/antd/antd_select.dart';

void main() {
  Future<void> pumpTransferScreen(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final state = AppState()
      ..hosts = [
        Host(id: 1, name: 'alpha', host: '10.0.0.1'),
        Host(id: 2, name: 'beta', host: '10.0.0.2'),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: FileTransferScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders two host panels without desktop overflow',
      (tester) async {
    await pumpTransferScreen(tester, const Size(1440, 900));

    expect(find.byType(AntdSelect<int>), findsNWidgets(2));
    expect(find.text('选择服务器'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stacks both host panels without mobile overflow',
      (tester) async {
    await pumpTransferScreen(tester, const Size(390, 844));

    expect(find.byType(AntdSelect<int>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
