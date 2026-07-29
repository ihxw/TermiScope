import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termiscope_mobile/models/models.dart';
import 'package:termiscope_mobile/providers/app_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('terminal tabs switch existing by default and can force a new session',
      () async {
    final state = AppState();
    final host = Host(id: 7, name: 'server', host: '10.0.0.7');

    state.addTerminal(host);
    final firstTab = state.activeTabId;
    state.addTerminal(host);
    expect(state.activeTerminals, hasLength(1));
    expect(state.activeTabId, firstTab);

    await Future<void>.delayed(const Duration(milliseconds: 1));
    state.addTerminal(host, forceNew: true);
    expect(state.activeTerminals, hasLength(2));
    expect(state.activeTabId, isNot(firstTab));
  });

  test('local network host preference is scoped to the configured server',
      () async {
    final state = AppState();
    state.apiService.baseUrl = 'https://server-a.example';

    await state.setLocalNetworkHost(7, true);
    expect(state.isLocalNetworkHost(7), isTrue);
    expect(
      (await SharedPreferences.getInstance())
          .getStringList('local_network_host_keys'),
      contains('https://server-a.example|7'),
    );

    state.apiService.baseUrl = 'https://server-b.example';
    expect(state.isLocalNetworkHost(7), isFalse);

    state.apiService.baseUrl = 'https://server-a.example';
    await state.setLocalNetworkHost(7, false);
    expect(state.isLocalNetworkHost(7), isFalse);
  });
}
