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
        Host(
          id: 2,
          name: 'monitor-beta',
          host: '10.0.0.2',
          monitorEnabled: true,
          netTrafficLimit: 1073741824,
          netResetDay: 1,
        ),
        Host(
          id: 3,
          name: 'monitor-gamma',
          host: '10.0.0.3',
          monitorEnabled: true,
          expirationDate: '2027-07-18',
          billingAmount: 12,
          billingPeriod: 'monthly',
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
        '2': {
          'host_id': 2,
          'status': 'online',
          'hostname': 'beta-node',
          'agent_version': '1.0.0',
          'net_monthly_rx': 1048576,
          'net_monthly_tx': 2097152,
        },
        '3': {
          'host_id': 3,
          'status': 'online',
          'hostname': 'gamma-node',
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

  testWidgets('stretches cards with different content to an equal row height',
      (tester) async {
    await pumpMonitor(tester, const Size(1440, 900));

    final heights = [1, 2, 3]
        .map((id) => tester
            .getSize(find.byKey(ValueKey('monitor-card-$id')))
            .height)
        .toSet();
    expect(heights, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the monitor toolbar without mobile layout errors',
      (tester) async {
    await pumpMonitor(tester, const Size(390, 844));

    expect(find.text('monitor-alpha'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
