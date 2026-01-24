import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/providers/hosts_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

class NetworkDetailPage extends ConsumerStatefulWidget {
  final int hostId;

  const NetworkDetailPage({super.key, required this.hostId});

  @override
  ConsumerState<NetworkDetailPage> createState() => _NetworkDetailPageState();
}

class _NetworkDetailPageState extends ConsumerState<NetworkDetailPage> {
  String _selectedRange = '1h';
  List<Map<String, dynamic>> _networkData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNetworkData();
  }

  Future<void> _loadNetworkData() async {
    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get(
        '/ssh-hosts/${widget.hostId}/network/tasks',
      );

      setState(() {
        _networkData = List<Map<String, dynamic>>.from(response ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hostsStateProvider);
    final host = state.hosts.firstWhere(
      (h) => h.id == widget.hostId,
      orElse: () => throw Exception('Host not found'),
    );
    final monitor = state.monitorData[widget.hostId] ?? host.monitorData;

    return Scaffold(
      appBar: AppBar(
        title: Text(host.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNetworkData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 当前状态卡片
                  _buildCurrentStatusCard(monitor),
                  const SizedBox(height: 24),

                  // 时间范围选择
                  Row(
                    children: [
                      const Text(
                        '网络流量',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _buildRangeSelector(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 流量图表
                  _buildNetworkChart(),
                  const SizedBox(height: 24),

                  // 接口列表
                  const Text(
                    '网络接口',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInterfaceList(),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentStatusCard(dynamic monitor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前状态',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (monitor != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.download,
                      label: '下载速率',
                      value: _formatSpeed(monitor.networkRx),
                      color: AppTheme.successColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.upload,
                      label: '上传速率',
                      value: _formatSpeed(monitor.networkTx),
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.memory,
                      label: 'CPU',
                      value: '${monitor.cpuUsage.toStringAsFixed(1)}%',
                      color: _getProgressColor(monitor.cpuUsage),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.storage,
                      label: '内存',
                      value: '${monitor.memoryUsage.toStringAsFixed(1)}%',
                      color: _getProgressColor(monitor.memoryUsage),
                    ),
                  ),
                ],
              ),
            ] else
              const Center(
                child: Text(
                  '暂无监控数据',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: '1h', label: Text('1小时')),
        ButtonSegment(value: '6h', label: Text('6小时')),
        ButtonSegment(value: '24h', label: Text('24小时')),
      ],
      selected: {_selectedRange},
      onSelectionChanged: (value) {
        setState(() => _selectedRange = value.first);
        _loadNetworkData();
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildNetworkChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 200,
          child: _networkData.isEmpty
              ? const Center(
                  child: Text(
                    '暂无流量数据',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: Colors.grey.shade800,
                          strokeWidth: 1,
                        );
                      },
                    ),
                    titlesData: const FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // 下载
                      LineChartBarData(
                        spots: const [
                          FlSpot(0, 1),
                          FlSpot(1, 2),
                          FlSpot(2, 1.5),
                          FlSpot(3, 3),
                          FlSpot(4, 2),
                        ],
                        isCurved: true,
                        color: AppTheme.successColor,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppTheme.successColor.withOpacity(0.1),
                        ),
                      ),
                      // 上传
                      LineChartBarData(
                        spots: const [
                          FlSpot(0, 0.5),
                          FlSpot(1, 1),
                          FlSpot(2, 0.8),
                          FlSpot(3, 1.5),
                          FlSpot(4, 1),
                        ],
                        isCurved: true,
                        color: AppTheme.primaryColor,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppTheme.primaryColor.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInterfaceList() {
    if (_networkData.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.network_check,
                    size: 48, color: Colors.grey.shade600),
                const SizedBox(height: 8),
                Text(
                  '暂无网络接口数据',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: _networkData.map((iface) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.network_wifi,
                color: AppTheme.primaryColor,
              ),
            ),
            title: Text(iface['interface_name'] ?? 'Unknown'),
            subtitle: Text(iface['display_name'] ?? ''),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '↓ ${_formatBytes(iface['rx_bytes'] ?? 0)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.successColor),
                ),
                Text(
                  '↑ ${_formatBytes(iface['tx_bytes'] ?? 0)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.primaryColor),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getProgressColor(double value) {
    if (value >= 90) return AppTheme.errorColor;
    if (value >= 70) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
    } else if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '$bytes B';
    }
  }
}
