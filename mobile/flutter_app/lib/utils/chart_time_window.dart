class ChartTimeWindow {
  const ChartTimeWindow({required this.min, required this.max});

  final DateTime min;
  final DateTime max;

  Duration get span => max.difference(min);
}

Duration parseChartRange(String range) {
  final match = RegExp(r'^(\d+)([hd])$').firstMatch(range);
  if (match == null) return const Duration(hours: 24);

  final value = int.tryParse(match.group(1) ?? '');
  if (value == null || value <= 0) return const Duration(hours: 24);

  return match.group(2) == 'd' ? Duration(days: value) : Duration(hours: value);
}

ChartTimeWindow resolveChartTimeWindow({
  required Iterable<DateTime> timestamps,
  required String range,
  DateTime? end,
}) {
  final requestedMax = end ?? DateTime.now();
  final requestedSpan = parseChartRange(range);
  final requestedWindow = ChartTimeWindow(
    min: requestedMax.subtract(requestedSpan),
    max: requestedMax,
  );

  DateTime? dataMin;
  DateTime? dataMax;
  for (final timestamp in timestamps) {
    if (dataMin == null || timestamp.isBefore(dataMin)) dataMin = timestamp;
    if (dataMax == null || timestamp.isAfter(dataMax)) dataMax = timestamp;
  }
  if (dataMin == null || dataMax == null) return requestedWindow;

  final dataSpanMs = dataMax.difference(dataMin).inMilliseconds;
  final requestedSpanMs = requestedSpan.inMilliseconds;
  if (dataSpanMs >= requestedSpanMs * 0.8) return requestedWindow;

  final proportionalPadding = (dataSpanMs * 0.03).round();
  final minimumPadding = (requestedSpanMs * 0.01).round().clamp(0, 60000);
  final padding = Duration(
    milliseconds: proportionalPadding > minimumPadding
        ? proportionalPadding
        : minimumPadding,
  );
  return ChartTimeWindow(
    min: dataMin.subtract(padding),
    max: dataMax.add(padding),
  );
}
