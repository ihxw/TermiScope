import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MonitorChart extends StatelessWidget {
  final String title;
  final List<FlSpot> data;
  final Color lineColor;
  final Color gradientColor;
  final String? Function(double)? bottomTitle;
  final String? Function(double)? leftTitle;

  const MonitorChart({
    super.key,
    required this.title,
    required this.data,
    required this.lineColor,
    required this.gradientColor,
    this.bottomTitle,
    this.leftTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.7,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: data.length > 10 ? (data.length / 5).roundToDouble() : 1,
                        getTitlesWidget: (value, meta) {
                          if (bottomTitle != null) {
                            final title = bottomTitle!(value);
                            if (title != null) {
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(title, style: const TextStyle(fontSize: 10)),
                              );
                            }
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text('', style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (leftTitle != null) {
                            final title = leftTitle!(value);
                            if (title != null) {
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(title, style: const TextStyle(fontSize: 10)),
                              );
                            }
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text('', style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: data.isEmpty ? 0 : data.length - 1.toDouble(),
                  minY: 0,
                  maxY: data.isEmpty ? 100 : data.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.1,
                  lineBarsData: [
                    LineChartBarData(
                      spots: data,
                      isCurved: true,
                      color: lineColor,
                      barWidth: 2,
                      belowBarData: BarAreaData(
                        show: true,
                        color: gradientColor.withValues(alpha: 0.3),
                      ),
                      dotData: const FlDotData(show: false),
                      preventCurveOverShooting: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}