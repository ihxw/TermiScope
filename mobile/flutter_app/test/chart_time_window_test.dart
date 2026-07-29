import 'package:flutter_test/flutter_test.dart';
import 'package:termiscope_mobile/utils/chart_time_window.dart';

void main() {
  final end = DateTime.utc(2026, 7, 18, 12);

  test('keeps the selected range when data covers at least 80 percent', () {
    final window = resolveChartTimeWindow(
      timestamps: [end.subtract(const Duration(hours: 20)), end],
      range: '24h',
      end: end,
    );

    expect(window.min, end.subtract(const Duration(hours: 24)));
    expect(window.max, end);
  });

  test('fits sparse data with a small padding', () {
    final first = end.subtract(const Duration(hours: 2));
    final window = resolveChartTimeWindow(
      timestamps: [first, end],
      range: '24h',
      end: end,
    );

    expect(window.min, first.subtract(const Duration(minutes: 3, seconds: 36)));
    expect(window.max, end.add(const Duration(minutes: 3, seconds: 36)));
  });

  test('uses a visible window for a single point', () {
    final window = resolveChartTimeWindow(
      timestamps: [end],
      range: '1h',
      end: end,
    );

    expect(window.min, end.subtract(const Duration(seconds: 36)));
    expect(window.max, end.add(const Duration(seconds: 36)));
  });

  test('falls back to 24 hours for an invalid range', () {
    expect(parseChartRange('invalid'), const Duration(hours: 24));
  });
}
