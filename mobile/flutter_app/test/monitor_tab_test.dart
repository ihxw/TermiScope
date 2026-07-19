import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termiscope_mobile/models/models.dart';
import 'package:termiscope_mobile/providers/app_state.dart';
import 'package:termiscope_mobile/screens/monitor_tab.dart';

void main() {
  Future<void> pumpMonitor(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'monitor_view_mode': 'card'});

    final state = AppState()
      ..hosts = [
        Host(
          id: 1,
          name: 'monitor-alpha',
          host: '10.0.0.1',
          monitorEnabled: true,
        ),
      ]
      ..monitorConnected = true
      ..monitorData = {
        '1': {
          'host_id': 1,
          'status': 'online',
          'hostname': 'alpha-node',
          'cpu': 20,
          'memory': 35,
          'disk': 40,
        },
      };

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: MonitorTab()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders monitored hosts on a desktop viewport', (tester) async {
    await pumpMonitor(tester, const Size(1440, 900));

    expect(find.text('monitor-alpha'), findsWidgets);
    expect(find.textContaining('1'), findsWidgets);
    expect(tester.getSize(find.byType(MonitorTab)).width, 1440);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the monitor toolbar without mobile layout errors',
      (tester) async {
    await pumpMonitor(tester, const Size(390, 844));

    expect(find.text('monitor-alpha'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
