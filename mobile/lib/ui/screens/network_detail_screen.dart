import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile/l10n/app_localizations.dart';
import '../widgets/monitor_chart.dart';
import 'package:fl_chart/fl_chart.dart';

class NetworkDetailScreen extends StatefulWidget {
  final int hostId;
  
  const NetworkDetailScreen({
    super.key,
    required this.hostId,
  });

  @override
  State<NetworkDetailScreen> createState() => _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends State<NetworkDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Network Monitoring'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Network Statistics',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              
              // Network RX/TX charts
              MonitorChart(
                title: 'RX Rate',
                data: _generateSampleData(50),
                lineColor: Colors.blue,
                gradientColor: Colors.blue,
                bottomTitle: (value) => '${value.toInt()}s',
                leftTitle: (value) => '${value.toInt()} KB/s',
              ),
              const SizedBox(height: 16),
              
              MonitorChart(
                title: 'TX Rate',
                data: _generateSampleData(30),
                lineColor: Colors.green,
                gradientColor: Colors.green,
                bottomTitle: (value) => '${value.toInt()}s',
                leftTitle: (value) => '${value.toInt()} KB/s',
              ),
              const SizedBox(height: 16),
              
              // Ping/latency chart
              MonitorChart(
                title: 'Ping Latency',
                data: _generateSampleData(100, maxValue: 200),
                lineColor: Colors.orange,
                gradientColor: Colors.orange,
                bottomTitle: (value) => '${value.toInt()}s',
                leftTitle: (value) => '${value.toInt()} ms',
              ),
              const SizedBox(height: 16),
              
              // Packet loss chart
              MonitorChart(
                title: 'Packet Loss',
                data: _generateSampleData(5, maxValue: 100),
                lineColor: Colors.red,
                gradientColor: Colors.red,
                bottomTitle: (value) => '${value.toInt()}s',
                leftTitle: (value) => '${value.toInt()}%',
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<FlSpot> _generateSampleData(int baseValue, {int maxValue = 100}) {
    // Generate sample data for the last 60 seconds
    return List.generate(60, (index) {
      // Add some variation to the data
      final variation = (baseValue * 0.2 * (0.5 - Random().nextDouble())).abs();
      final value = baseValue + variation;
      return FlSpot(index.toDouble(), value.clamp(0.0, maxValue.toDouble()));
    });
  }
}