import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:termiscope_mobile/models/models.dart';
import 'package:termiscope_mobile/providers/app_state.dart';
import 'package:termiscope_mobile/screens/host_management_screen.dart';

void main() {
  Future<AppState> pumpHosts(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final state = AppState()
      ..profile = UserProfile(id: 1, username: 'tester')
      ..hosts = [
        Host(
          id: 1,
          name: 'primary-host',
          host: '10.0.0.1',
          port: 2222,
          username: 'deploy',
          groupName: 'production',
          description: 'Primary server',
          hostType: 'monitor_only',
          monitorEnabled: true,
        ),
        Host(
          id: 2,
          name: 'deleted-host',
          host: '10.0.0.2',
          hostType: 'monitor_only',
          deletedAt: DateTime.utc(2026, 7, 18),
        ),
      ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(
            body: HostManagementScreen(autoLoad: false),
          ),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets(
      'shows detailed desktop columns and hides deleted hosts by default',
      (tester) async {
    await pumpHosts(tester, const Size(1440, 900));

    expect(find.text('端口'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('分组'), findsOneWidget);
    expect(find.text('primary-host'), findsOneWidget);
    expect(find.text('deleted-host'), findsNothing);

    await tester.tap(find.text('显示已删除'));
    await tester.pumpAndSettle();

    expect(find.text('deleted-host'), findsOneWidget);
    expect(find.text('已删除'), findsWidgets);
    expect(find.text('主机列表加载失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact columns and an action menu on mobile',
      (tester) async {
    await pumpHosts(tester, const Size(390, 844));

    expect(find.text('端口'), findsNothing);
    expect(find.text('用户名'), findsNothing);
    expect(find.text('分组'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
