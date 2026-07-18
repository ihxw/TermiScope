import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../widgets/antd/index.dart';
import '../utils/chart_time_window.dart';

class NetworkDetailScreen extends StatefulWidget {
  final int hostId;
  final String initialTab;

  const NetworkDetailScreen({
    super.key,
    required this.hostId,
    this.initialTab = 'connectivity',
  });

  @override
  State<NetworkDetailScreen> createState() => _NetworkDetailScreenState();
}

class _NetworkDetailScreenState extends State<NetworkDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingHost = false;
  bool _isLoadingStats = false;
  bool _isSaving = false;

  Host? _host;
  List<Map<String, dynamic>> _interfaces = [];
  double _monthlyRx = 0;
  double _monthlyTx = 0;

  // Latency Chart Data
  List<Map<String, dynamic>> _tasks = [];
  List<List<Offset>> _seriesPoints = [];
  List<String> _xAxisLabels = [];
  List<String> _yAxisLabels = [];
  List<Color> _seriesColors = [];
  String _timeRange = '24h';
  bool _isSmooth = true;

  // Config Form
  List<String> _selectedInterfaces = ['auto'];
  int _resetDay = 1;
  double _limitGb = 0.0;
  double _customTotalGb = 0.0;
  String _counterMode = 'total';

  // Notify Config
  bool _notifyOfflineEnabled = true;
  int _notifyOfflineThreshold = 1;
  bool _notifyTrafficEnabled = true;
  int _notifyTrafficThreshold = 90;
  List<String> _notifyChannels = ['email', 'telegram'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab == 'config' ? 1 : 0,
    );
    _tabController.addListener(() {
      setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _loadHost();
    _loadStats();
  }

  Future<void> _loadHost() async {
    setState(() => _isLoadingHost = true);
    final state = context.read<AppState>();
    await state.fetchHosts();
    if (mounted) {
      final found = state.hosts.where((h) => h.id == widget.hostId);
      if (found.isNotEmpty) {
        _host = found.first;
        _resetDay = _host!.netResetDay > 0 ? _host!.netResetDay : 1;
        _limitGb = (_host!.netTrafficLimit ?? 0.0) / (1024 * 1024 * 1024);
        _counterMode = _host!.netTrafficCounterMode;
        final adjBytes = _host!.netTrafficUsedAdjustment;
        final liveMetrics = state.monitorData[widget.hostId.toString()] ?? {};
        _monthlyRx = (liveMetrics['net_monthly_rx'] ?? 0.0).toDouble();
        _monthlyTx = (liveMetrics['net_monthly_tx'] ?? 0.0).toDouble();

        double measured = _counterMode == 'rx'
            ? _monthlyRx
            : _counterMode == 'tx'
                ? _monthlyTx
                : _monthlyRx + _monthlyTx;
        _customTotalGb = (measured + adjBytes) / (1024 * 1024 * 1024);

        if (_host!.host.contains(',')) {
          _selectedInterfaces = _host!.host.split(',');
        } else {
          _selectedInterfaces = ['auto'];
        }
      }
      _isLoadingHost = false;
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    final state = context.read<AppState>();
    final requestedEnd = DateTime.now();
    try {
      final res = await state.apiService.get(
          '/api/ssh-hosts/${widget.hostId}/network/latency-stats?range=$_timeRange');
      if (res is Map && mounted) {
        final taskList = res['tasks'] as List? ?? [];
        final seriesList = res['series'] as List? ?? [];

        _tasks = taskList.map((t) => Map<String, dynamic>.from(t)).toList();
        _seriesColors = _tasks.map((t) {
          final colorHex = t['color'] as String? ?? '#1890ff';
          try {
            return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
          } catch (_) {
            return AntdTokens.primary;
          }
        }).toList();

        // Process Series data
        _seriesPoints = [];
        DateTime? minTime, maxTime;
        double maxLatency = 10.0;

        List<List<Map<String, dynamic>>> parsedSeries = [];
        for (final s in seriesList) {
          final data = s['data'] as List? ?? [];
          final points = data.map((item) {
            final m = Map<String, dynamic>.from(item);
            final time = DateTime.parse(m['created_at']);
            final failed = m['success'] == false ||
                (m['latency'] is num && m['latency'] < 0);
            final double? lat =
                failed ? null : (m['latency'] as num?)?.toDouble();
            if (lat != null && lat > maxLatency) maxLatency = lat;
            if (minTime == null || time.isBefore(minTime!)) minTime = time;
            if (maxTime == null || time.isAfter(maxTime!)) maxTime = time;
            return {'time': time, 'latency': lat};
          }).toList();
          parsedSeries.add(points);
        }

        if (minTime != null && maxTime != null) {
          final visibleWindow = resolveChartTimeWindow(
            timestamps: parsedSeries.expand(
              (series) => series.map((point) => point['time'] as DateTime),
            ),
            range: _timeRange,
            end: requestedEnd,
          );
          final duration = visibleWindow.span.inMilliseconds;
          for (final s in parsedSeries) {
            final List<Offset> pts = [];
            for (final pt in s) {
              final time = pt['time'] as DateTime;
              final lat = pt['latency'] as double?;
              final double dx =
                  (time.difference(visibleWindow.min).inMilliseconds / duration)
                      .clamp(0.0, 1.0);
              final double dy = lat == null ? 0.0 : (lat / maxLatency);
              pts.add(Offset(dx, dy));
            }
            _seriesPoints.add(pts);
          }

          // X Labels (3 points)
          String formatTime(DateTime dt) {
            if (_timeRange.endsWith('d')) {
              final month = dt.month.toString().padLeft(2, '0');
              final day = dt.day.toString().padLeft(2, '0');
              return '$month-$day';
            }
            final h = dt.hour.toString().padLeft(2, '0');
            final m = dt.minute.toString().padLeft(2, '0');
            return '$h:$m';
          }

          final labelSpan = visibleWindow.span;
          _xAxisLabels = [
            formatTime(visibleWindow.min),
            formatTime(visibleWindow.min.add(labelSpan ~/ 2)),
            formatTime(visibleWindow.max),
          ];

          // Y Labels (4 points)
          _yAxisLabels = [
            '0',
            (maxLatency * 0.33).toStringAsFixed(1),
            (maxLatency * 0.66).toStringAsFixed(1),
            maxLatency.toStringAsFixed(1),
          ];
        } else {
          _seriesPoints = [];
          _xAxisLabels = [];
          _yAxisLabels = [];
        }

        // Load interfaces from state
        final liveMetrics = state.monitorData[widget.hostId.toString()] ?? {};
        final ifaces = liveMetrics['interfaces'] as List? ?? [];
        _interfaces = ifaces.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      print('Load stats error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    final state = context.read<AppState>();
    try {
      final measuredTraffic = _counterMode == 'rx'
          ? _monthlyRx
          : _counterMode == 'tx'
              ? _monthlyTx
              : _monthlyRx + _monthlyTx;
      final double targetTotalBytes = _customTotalGb * 1024 * 1024 * 1024;
      final bool resetTraffic = targetTotalBytes < measuredTraffic;
      final double trafficAdj =
          resetTraffic ? targetTotalBytes : targetTotalBytes - measuredTraffic;

      final double limitBytes = _limitGb * 1024 * 1024 * 1024;

      final ok = await state.updateHost(_host!.id.toString(), {
        'net_interface': _selectedInterfaces.join(','),
        'net_reset_day': _resetDay,
        'net_traffic_limit': limitBytes.toInt(),
        'net_traffic_used_adjustment': trafficAdj.toInt(),
        'net_traffic_counter_mode': _counterMode,
        'reset_traffic': resetTraffic,
      });

      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('网卡配置保存成功'), backgroundColor: AntdTokens.success),
          );
        }
        _loadAll();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('保存配置失败'), backgroundColor: AntdTokens.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('保存发生错误: $e'), backgroundColor: AntdTokens.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveNotifyConfig() async {
    setState(() => _isSaving = true);
    final state = context.read<AppState>();
    try {
      final ok = await state.updateHost(_host!.id.toString(), {
        'notify_offline_enabled': _notifyOfflineEnabled,
        'notify_offline_threshold': _notifyOfflineThreshold,
        'notify_traffic_enabled': _notifyTrafficEnabled,
        'notify_traffic_threshold': _notifyTrafficThreshold,
        'notify_channels': _notifyChannels.join(','),
      });

      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('告警通知配置保存成功'),
                backgroundColor: AntdTokens.success),
          );
        }
        _loadAll();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('保存告警配置失败'), backgroundColor: AntdTokens.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('保存发生错误: $e'), backgroundColor: AntdTokens.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(k)).floor();
    return '${(bytes / pow(k, i)).toStringAsFixed(1)} ${sizes[i]}';
  }

  String _formatSpeed(double bytesPerSec) {
    return '${_formatBytes(bytesPerSec)}/s';
  }

  Widget _buildConnectivityTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        AntdCard(
          title: const Text('网络连通性 (Ping)'),
          extra: Row(children: [
            AntdButton(
              size: AntdSize.small,
              icon: Icons.refresh,
              loading: _isLoadingStats,
              onPressed: _loadStats,
            ),
            const SizedBox(width: 6),
            AntdButton(
              size: AntdSize.small,
              type: _isSmooth
                  ? AntdButtonType.primary
                  : AntdButtonType.defaultType,
              onPressed: () => setState(() => _isSmooth = !_isSmooth),
              child: Text(_isSmooth ? '平滑' : '折线'),
            ),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: _timeRange,
              dropdownColor: AntdTokens.containerColor(context),
              style:
                  TextStyle(color: AntdTokens.textColor(context), fontSize: 12),
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '1h', child: Text('1h')),
                DropdownMenuItem(value: '8h', child: Text('8h')),
                DropdownMenuItem(value: '16h', child: Text('16h')),
                DropdownMenuItem(value: '24h', child: Text('24h')),
                DropdownMenuItem(value: '7d', child: Text('7d')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _timeRange = v);
                  _loadStats();
                }
              },
            ),
          ]),
          child: SizedBox(
            height: 300,
            child: _seriesPoints.isEmpty
                ? const Center(child: AntdEmpty(description: '暂无连通性测试数据'))
                : AntdLineChart(
                    series: _seriesPoints,
                    colors: _seriesColors,
                    xAxisLabels: _xAxisLabels,
                    yAxisLabels: _yAxisLabels,
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _buildConfigTab(BuildContext context) {
    final state = context.watch<AppState>();
    final double measured = _counterMode == 'rx'
        ? _monthlyRx
        : _counterMode == 'tx'
            ? _monthlyTx
            : _monthlyRx + _monthlyTx;
    final double adjBytes = (_host?.netTrafficUsedAdjustment ?? 0.0);
    final double totalUsedBytes = measured + adjBytes;
    final double limitBytes = _limitGb * 1024 * 1024 * 1024;
    final double remainingBytes =
        limitBytes - totalUsedBytes > 0 ? limitBytes - totalUsedBytes : 0;
    final int usagePct = limitBytes > 0
        ? ((totalUsedBytes / limitBytes) * 100).round().clamp(0, 100)
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        AntdCard(
          title: const Text('流量统计与限额配置'),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Config Form
            AntdFormItem(
              label: '网卡接口 (支持逗号分隔多个网卡)',
              child: AntdInput(
                controller:
                    TextEditingController(text: _selectedInterfaces.join(',')),
                placeholder: 'e.g. eth0, auto',
                onChanged: (v) => _selectedInterfaces = v.split(','),
              ),
            ),
            const SizedBox(height: 12),
            AntdFormItem(
              label: '每月流量重置日期 (1-31)',
              child: DropdownButton<int>(
                value: _resetDay,
                isExpanded: true,
                dropdownColor: AntdTokens.containerColor(context),
                items: List.generate(31, (i) => i + 1)
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n 号')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _resetDay = v);
                },
              ),
            ),
            const SizedBox(height: 12),
            AntdFormItem(
              label: '月度流量限额 (GB, 0为无限流量)',
              child: AntdInput(
                controller:
                    TextEditingController(text: _limitGb.toStringAsFixed(2)),
                placeholder: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => _limitGb = double.tryParse(v) ?? 0.0,
              ),
            ),
            const SizedBox(height: 12),
            AntdFormItem(
              label: '已使用流量校准 (GB, 重新同步累加流量值)',
              child: AntdInput(
                controller: TextEditingController(
                    text: _customTotalGb.toStringAsFixed(2)),
                placeholder: '0.00',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => _customTotalGb = double.tryParse(v) ?? 0.0,
              ),
            ),
            const SizedBox(height: 12),
            AntdFormItem(
              label: '计费流量模式',
              child: DropdownButton<String>(
                value: _counterMode,
                isExpanded: true,
                dropdownColor: AntdTokens.containerColor(context),
                items: const [
                  DropdownMenuItem(value: 'total', child: Text('双向流入+流出')),
                  DropdownMenuItem(value: 'tx', child: Text('单向流出 (Outbound)')),
                  DropdownMenuItem(value: 'rx', child: Text('单向流入 (Inbound)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _counterMode = v);
                },
              ),
            ),
            const SizedBox(height: 16),
            AntdButton(
              type: AntdButtonType.primary,
              loading: _isSaving,
              onPressed: _saveConfig,
              block: true,
              child: const Text('保存网卡及流量限额配置'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            // Monthly Traffic usage card info
            Text('月度流量监控报表',
                style: TextStyle(
                    fontSize: AntdTokens.fontSizeLG,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Column(children: [
                  const Text('流入 (Inbound)',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(_formatBytes(_monthlyRx),
                      style: const TextStyle(
                          color: AntdTokens.success,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: Column(children: [
                  const Text('流出 (Outbound)',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(_formatBytes(_monthlyTx),
                      style: const TextStyle(
                          color: AntdTokens.error,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            if (_limitGb > 0) ...[
              const SizedBox(height: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('使用进度 ($usagePct%)',
                          style: const TextStyle(fontSize: 12)),
                      Text(
                          '${_formatBytes(totalUsedBytes)} / ${_limitGb.toStringAsFixed(0)} GB',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                const SizedBox(height: 6),
                AntdProgress(
                    percent: usagePct.toDouble(),
                    strokeWidth: 8,
                    color:
                        usagePct >= 90 ? AntdTokens.error : AntdTokens.primary),
                const SizedBox(height: 6),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('剩余配额: ${_formatBytes(remainingBytes)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                      Text('重置周期: 每月 $_resetDay 号',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ]),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildInterfacesTab(BuildContext context) {
    final columns = <AntdTableColumn<Map<String, dynamic>>>[
      AntdTableColumn(
        title: '网卡接口',
        width: 120,
        cell: (ctx, row, _) => Row(children: [
          const Icon(Icons.settings_ethernet, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(row['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      AntdTableColumn(
        title: 'IP地址',
        width: 180,
        cell: (ctx, row, _) {
          final ips = row['ips'] as List? ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: ips
                .map((ip) =>
                    Text(ip.toString(), style: const TextStyle(fontSize: 11)))
                .toList(),
          );
        },
      ),
      AntdTableColumn(
        title: '实时速度',
        width: 160,
        cell: (ctx, row, _) => Row(children: [
          const Icon(Icons.arrow_downward, size: 12, color: AntdTokens.success),
          Text(_formatSpeed((row['rx_rate'] ?? 0).toDouble()),
              style: const TextStyle(color: AntdTokens.success, fontSize: 11)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_upward, size: 12, color: AntdTokens.primary),
          Text(_formatSpeed((row['tx_rate'] ?? 0).toDouble()),
              style: const TextStyle(color: AntdTokens.primary, fontSize: 11)),
        ]),
      ),
      AntdTableColumn(
        title: '总流量',
        width: 140,
        cell: (ctx, row, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rx: ${_formatBytes((row['rx'] ?? 0).toDouble())}',
                style: const TextStyle(fontSize: 11)),
            Text('Tx: ${_formatBytes((row['tx'] ?? 0).toDouble())}',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
      AntdTableColumn(
        title: 'MAC 地址',
        width: 140,
        cell: (ctx, row, _) => Text(row['mac'] ?? '--',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: AntdCard(
        title: const Text('网卡硬件接口列表'),
        child: SizedBox(
          height: 400,
          child: _interfaces.isEmpty
              ? const Center(child: AntdEmpty(description: '暂无活动网卡数据'))
              : AntdTable<Map<String, dynamic>>(
                  rowKey: (row) => row['name']?.toString() ?? '',
                  columns: columns,
                  data: _interfaces,
                ),
        ),
      ),
    );
  }

  Widget _buildNotificationsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        AntdCard(
          title: const Text('主机及告警通知设置'),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Offline notify switch
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('离线宕机通知',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              AntdSwitch(
                value: _notifyOfflineEnabled,
                onChanged: (v) => setState(() => _notifyOfflineEnabled = v),
              ),
            ]),
            const SizedBox(height: 12),
            if (_notifyOfflineEnabled) ...[
              AntdFormItem(
                label: '连续离线阈值 (分钟)',
                child: AntdInput(
                  controller: TextEditingController(
                      text: _notifyOfflineThreshold.toString()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(
                      () => _notifyOfflineThreshold = int.tryParse(v) ?? 1),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const SizedBox(height: 12),
            // Traffic limit notify
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('流量限额提醒通知',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              AntdSwitch(
                value: _notifyTrafficEnabled,
                onChanged: (v) => setState(() => _notifyTrafficEnabled = v),
              ),
            ]),
            const SizedBox(height: 12),
            if (_notifyTrafficEnabled) ...[
              AntdFormItem(
                label: '流量预警阈值比例 (%)',
                child: Slider(
                  value: _notifyTrafficThreshold.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '$_notifyTrafficThreshold%',
                  activeColor: AntdTokens.primary,
                  onChanged: (v) =>
                      setState(() => _notifyTrafficThreshold = v.toInt()),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const SizedBox(height: 12),
            // Channel Checklist
            const Text('通知发送渠道 (支持多选)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('电子邮件 (Email)'),
              value: _notifyChannels.contains('email'),
              activeColor: AntdTokens.primary,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _notifyChannels.add('email');
                  } else {
                    _notifyChannels.remove('email');
                  }
                });
              },
            ),
            CheckboxListTile(
              title: const Text('Telegram 机器人'),
              value: _notifyChannels.contains('telegram'),
              activeColor: AntdTokens.primary,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _notifyChannels.add('telegram');
                  } else {
                    _notifyChannels.remove('telegram');
                  }
                });
              },
            ),
            const SizedBox(height: 24),
            AntdButton(
              type: AntdButtonType.primary,
              loading: _isSaving,
              onPressed: _saveNotifyConfig,
              block: true,
              child: const Text('保存通知配置'),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingHost) {
      return const Scaffold(body: Center(child: AntdSpin(tip: '加载中...')));
    }

    final hostTitle = _host?.name ?? '网络详情';

    return Scaffold(
      appBar: AppBar(
        title: Text(hostTitle),
        elevation: 0,
        backgroundColor: AntdTokens.containerColor(context),
        foregroundColor: AntdTokens.textColor(context),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AntdTokens.primary,
          unselectedLabelColor: AntdTokens.secondaryTextColor(context),
          indicatorColor: AntdTokens.primary,
          tabs: const [
            Tab(text: '网络监控'),
            Tab(text: '网卡配置'),
            Tab(text: '网卡接口'),
            Tab(text: '告警通知'),
          ],
        ),
      ),
      body: Container(
        color: AntdTokens.pageColor(context),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildConnectivityTab(context),
            _buildConfigTab(context),
            _buildInterfacesTab(context),
            _buildNotificationsTab(context),
          ],
        ),
      ),
    );
  }
}

class AntdLineChart extends StatelessWidget {
  final List<List<Offset>> series;
  final List<Color> colors;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;

  const AntdLineChart({
    super.key,
    required this.series,
    required this.colors,
    required this.xAxisLabels,
    required this.yAxisLabels,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    final gridColor =
        isDark ? const Color(0xFF303030) : const Color(0xFFF0F0F0);
    final labelColor = isDark ? Colors.white60 : Colors.black45;

    return CustomPaint(
      painter: _LineChartPainter(
        series: series,
        colors: colors,
        xAxisLabels: xAxisLabels,
        yAxisLabels: yAxisLabels,
        gridColor: gridColor,
        labelColor: labelColor,
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<List<Offset>> series;
  final List<Color> colors;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;
  final Color gridColor;
  final Color labelColor;

  _LineChartPainter({
    required this.series,
    required this.colors,
    required this.xAxisLabels,
    required this.yAxisLabels,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double leftMargin = 50.0;
    const double bottomMargin = 30.0;
    const double rightMargin = 20.0;
    const double topMargin = 20.0;

    final double chartWidth = size.width - leftMargin - rightMargin;
    final double chartHeight = size.height - topMargin - bottomMargin;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Y Axis Grid & Labels
    final int yCount = yAxisLabels.length;
    for (int i = 0; i < yCount; i++) {
      final double y = topMargin + chartHeight * (1.0 - i / (yCount - 1));
      canvas.drawLine(Offset(leftMargin, y),
          Offset(size.width - rightMargin, y), gridPaint);

      textPainter.text = TextSpan(
        text: yAxisLabels[i],
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
          canvas,
          Offset(
              leftMargin - textPainter.width - 8, y - textPainter.height / 2));
    }

    // X Axis Labels
    final int xCount = xAxisLabels.length;
    for (int i = 0; i < xCount; i++) {
      final double x = leftMargin + chartWidth * (i / (xCount - 1));
      canvas.drawLine(Offset(x, topMargin),
          Offset(x, size.height - bottomMargin), gridPaint);

      textPainter.text = TextSpan(
        text: xAxisLabels[i],
        style: TextStyle(color: labelColor, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas,
          Offset(x - textPainter.width / 2, size.height - bottomMargin + 6));
    }

    // Draw Lines
    for (int sIndex = 0; sIndex < series.length; sIndex++) {
      final s = series[sIndex];
      if (s.isEmpty) continue;

      final Color color = sIndex < colors.length ? colors[sIndex] : Colors.blue;
      final linePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;

      final fillPaint = Paint()
        ..color = color.withOpacity(0.1)
        ..style = PaintingStyle.fill;

      final path = Path();
      bool first = true;

      for (final pt in s) {
        final double x = leftMargin + pt.dx * chartWidth;
        final double y = topMargin + (1.0 - pt.dy) * chartHeight;

        if (first) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, linePaint);

      if (s.length > 1) {
        final fillPath = Path.from(path);
        final double lastX = leftMargin + s.last.dx * chartWidth;
        final double firstX = leftMargin + s.first.dx * chartWidth;
        fillPath.lineTo(lastX, topMargin + chartHeight);
        fillPath.lineTo(firstX, topMargin + chartHeight);
        fillPath.close();
        canvas.drawPath(fillPath, fillPaint);
      }

      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final dotStrokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      for (final pt in s) {
        final double x = leftMargin + pt.dx * chartWidth;
        final double y = topMargin + (1.0 - pt.dy) * chartHeight;
        canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
        canvas.drawCircle(Offset(x, y), 3.0, dotStrokePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.series != series || oldDelegate.colors != colors;
  }
}
