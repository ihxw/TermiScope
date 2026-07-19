import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/antd_tokens.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/responsive.dart';
import '../widgets/antd/index.dart';
import 'monitor_templates_screen.dart';
import 'network_detail_screen.dart';

class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key});

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<MonitorTab> {
  bool _cardMode = true;
  bool _batchUpdating = false;

  @override
  void initState() {
    super.initState();
    _restoreViewMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchServerAgentVersion();
    });
  }

  Future<void> _restoreViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _cardMode = prefs.getString('monitor_view_mode') != 'list');
  }

  Future<void> _setViewMode(String mode) async {
    setState(() => _cardMode = mode == 'card');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('monitor_view_mode', mode);
  }

  String _text(AppState state, String zh, String en) =>
      state.locale == 'zh' ? zh : en;

  bool _isAgentOutdated(AppState state, Host host, Map<String, dynamic> info) {
    final current = (info['agent_version'] ?? host.agentVersion)
        .toString()
        .replaceFirst(RegExp(r'^v'), '')
        .trim();
    final latest =
        state.serverAgentVersion.replaceFirst(RegExp(r'^v'), '').trim();
    return current.isNotEmpty && latest.isNotEmpty && current != latest;
  }

  Future<void> _batchUpdate(AppState state, List<Host> hosts) async {
    final outdated = hosts
        .where((host) {
          final info = _info(state, host);
          return _isAgentOutdated(state, host, info);
        })
        .map((host) => host.id)
        .toList();
    if (outdated.isEmpty) return;
    setState(() => _batchUpdating = true);
    final result = await state.updateMonitorAgents(outdated);
    if (!mounted) return;
    setState(() => _batchUpdating = false);
    final failed = result['failed'] ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${_text(state, 'Agent 更新完成', 'Agent update complete')}: '
        '${result['success']} / ${outdated.length}',
      ),
      backgroundColor: failed == 0 ? AntdTokens.success : AntdTokens.warning,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final hosts = state.hosts
          .where((host) => host.monitorEnabled && host.deletedAt == null)
          .toList();
      final onlineCount = hosts.where((host) {
        return state.monitorConnected &&
            _MonitorMetrics(_info(state, host)).online;
      }).length;
      final outdatedCount = hosts.where((host) {
        return _isAgentOutdated(state, host, _info(state, host));
      }).length;

      return Column(children: [
        if (!state.monitorConnected)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: AntdAlert(
              type: AntdAlertType.warning,
              message: _text(
                state,
                '监控实时连接已断开，正在自动重连',
                'Live monitor connection is unavailable. Reconnecting...',
              ),
              showIcon: true,
            ),
          ),
        AntdToolbar(height: 44, bordered: true, leading: [
          SizedBox(
            width: 160,
            child: AntdSegmented<String>(
              value: _cardMode ? 'card' : 'list',
              options: {
                'card': _text(state, '卡片', 'Cards'),
                'list': _text(state, '列表', 'List'),
              },
              onChanged: _setViewMode,
            ),
          ),
        ], trailing: [
          if (outdatedCount > 0) ...[
            AntdButton(
              size: AntdSize.small,
              type: AntdButtonType.primary,
              icon: Icons.system_update_alt,
              loading: _batchUpdating,
              onPressed:
                  _batchUpdating ? null : () => _batchUpdate(state, hosts),
              child: Text(
                '${_text(state, '批量更新 Agent', 'Update agents')} ($outdatedCount)',
              ),
            ),
            const SizedBox(width: 6),
          ],
          AntdButton(
            size: AntdSize.small,
            icon: Icons.history,
            onPressed: () => _showTrafficResetLogs(state),
            child: Text(_text(state, '重置日志', 'Reset logs')),
          ),
          const SizedBox(width: 6),
          AntdButton(
            size: AntdSize.small,
            icon: Icons.swap_vert,
            onPressed: () => _showReorderDialog(state, hosts),
          ),
          const SizedBox(width: 6),
          if (state.profile?.role == 'admin') ...[
            AntdButton(
              size: AntdSize.small,
              icon: Icons.app_registration,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MonitorTemplatesScreen(),
                ),
              ),
              child: Text(_text(state, '监控模板', 'Templates')),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${_text(state, '总计', 'Total')}: ${hosts.length}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Text(
            '${_text(state, '在线', 'Online')}: $onlineCount',
            style: const TextStyle(
              color: AntdTokens.success,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ]),
        Expanded(
          child: hosts.isEmpty
              ? AntdEmpty(
                  description: _text(state, '暂无监控主机', 'No monitored hosts'),
                )
              : _cardMode
                  ? _buildCardGrid(context, state, hosts)
                  : _buildTable(context, state, hosts),
        ),
      ]);
    });
  }

  Map<String, dynamic> _info(AppState state, Host host) {
    final raw = state.monitorData[host.id.toString()];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  Widget _buildCardGrid(
    BuildContext context,
    AppState state,
    List<Host> hosts,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = Responsive.crossAxisCountFromWidth(constraints.maxWidth);
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 388,
        ),
        itemCount: hosts.length,
        itemBuilder: (_, index) => _buildMonitorCard(state, hosts[index]),
      );
    });
  }

  Widget _buildTable(
    BuildContext context,
    AppState state,
    List<Host> hosts,
  ) {
    final columns = <AntdTableColumn<Host>>[
      AntdTableColumn(
        title: _text(state, '主机', 'Host'),
        width: 220,
        cell: (_, host, __) {
          final info = _info(state, host);
          final version =
              (info['agent_version'] ?? host.agentVersion).toString();
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(host.name, overflow: TextOverflow.ellipsis),
              Text(
                '${info['hostname'] ?? host.host}${version.isEmpty ? '' : ' · $version'}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
            ],
          );
        },
      ),
      AntdTableColumn(
        title: _text(state, '状态', 'Status'),
        width: 90,
        cell: (_, host, __) {
          final online = state.monitorConnected &&
              _MonitorMetrics(_info(state, host)).online;
          return AntdTag(
            preset: online ? AntdTagPreset.success : AntdTagPreset.error,
            label: online ? 'ONLINE' : 'OFFLINE',
          );
        },
      ),
      _metricColumn(state, 'CPU', 100, (m) => '${m.cpu.toStringAsFixed(1)}%'),
      _metricColumn(
        state,
        'RAM',
        145,
        (m) =>
            '${m.memoryPercent.toStringAsFixed(1)}%  ${_formatBytes(m.memUsed)}',
      ),
      _metricColumn(
        state,
        _text(state, '磁盘', 'Disk'),
        145,
        (m) =>
            '${m.diskPercent.toStringAsFixed(1)}%  ${_formatBytes(m.diskUsed)}',
      ),
      _metricColumn(
        state,
        _text(state, '网络', 'Network'),
        170,
        (m) => '↓${_formatBytes(m.rxRate)}/s  ↑${_formatBytes(m.txRate)}/s',
      ),
      AntdTableColumn(
        title: _text(state, '流量', 'Traffic'),
        width: 150,
        cell: (_, host, __) {
          final m = _MonitorMetrics(_info(state, host));
          final used = _trafficUsed(host, m);
          return Text(
            host.netTrafficLimit != null && host.netTrafficLimit! > 0
                ? '${_formatBytes(used)} / ${_formatBytes(host.netTrafficLimit!)}'
                : _formatBytes(used),
            style: const TextStyle(fontSize: 11),
          );
        },
      ),
      AntdTableColumn(
        title: _text(state, '财务', 'Finance'),
        width: 170,
        cell: (_, host, __) => Text(
          host.expirationDate == null
              ? '-'
              : '${host.expirationDate!.split('T').first} · ${host.currency}${host.billingAmount.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 11),
        ),
      ),
      AntdTableColumn(
        title: _text(state, '操作', 'Actions'),
        width: 150,
        cell: (_, host, __) => _buildActions(state, host),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        decoration: BoxDecoration(
          color: AntdTokens.containerColor(context),
          border: Border.all(color: AntdTokens.borderSecondaryColor(context)),
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: AntdTable<Host>(
          rowKey: (host) => host.id.toString(),
          data: hosts,
          columns: columns,
          rowHeight: 58,
        ),
      ),
    );
  }

  AntdTableColumn<Host> _metricColumn(
    AppState state,
    String title,
    double width,
    String Function(_MonitorMetrics metrics) value,
  ) {
    return AntdTableColumn(
      title: title,
      width: width,
      cell: (_, host, __) => Text(
        value(_MonitorMetrics(_info(state, host))),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildMonitorCard(AppState state, Host host) {
    final info = _info(state, host);
    final metrics = _MonitorMetrics(info);
    final online = state.monitorConnected && metrics.online;
    final version = (info['agent_version'] ?? host.agentVersion).toString();
    final updateStatus = info['agent_update_status']?.toString() ?? '';
    final outdated = _isAgentOutdated(state, host, info);
    final trafficUsed = _trafficUsed(host, metrics);
    final limit = host.netTrafficLimit ?? 0;
    final trafficPercent =
        limit > 0 ? (trafficUsed / limit * 100).clamp(0, 100).toDouble() : 0.0;

    final card = AntdMetricCard(
      title: host.name,
      value: online ? 'ONLINE' : 'OFFLINE',
      subtitle: [
        info['hostname']?.toString() ?? host.host,
        if (version.isNotEmpty) 'Agent $version',
      ].join(' · '),
      status:
          online ? AntdStatusBadgeStatus.online : AntdStatusBadgeStatus.offline,
      statusText: online ? 'ONLINE' : 'OFFLINE',
      icon: Icons.dns_outlined,
      iconColor:
          online ? AntdTokens.success : AntdTokens.secondaryTextColor(context),
      actions: _cardActions(state, host, outdated),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.desktop_windows,
                size: 12, color: AntdTokens.secondaryTextColor(context)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${info['os'] ?? 'Unknown'} · ${_formatUptime(metrics.uptime)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AntdTokens.secondaryTextColor(context),
                ),
              ),
            ),
          ]),
          if (metrics.cpuModel.isNotEmpty || metrics.cpuCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${metrics.cpuModel}${metrics.cpuCount > 0 ? ' · ${metrics.cpuCount} cores' : ''}'
              '${metrics.cpuMhz > 0 ? ' · ${metrics.cpuMhz.toStringAsFixed(0)} MHz' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: AntdTokens.secondaryTextColor(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _progressRow('CPU', metrics.cpu, AntdTokens.primary),
          const SizedBox(height: 6),
          _progressRow(
            'RAM',
            metrics.memoryPercent,
            AntdTokens.warning,
            detail:
                '${_formatBytes(metrics.memUsed)}/${_formatBytes(metrics.memTotal)}',
          ),
          const SizedBox(height: 6),
          AntdPopover(
            width: 300,
            title: Text(_text(state, '磁盘明细', 'Disk details')),
            content: metrics.disks.isEmpty
                ? Text(_text(state, '暂无磁盘数据', 'No disk data'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: metrics.disks.map((disk) {
                      final used = _number(disk['used']);
                      final total = max(_number(disk['total']), 1);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _progressRow(
                          (disk['mount'] ?? disk['path'] ?? '-').toString(),
                          used / total * 100,
                          const Color(0xFF722ED1),
                          detail:
                              '${_formatBytes(used)}/${_formatBytes(total)}',
                        ),
                      );
                    }).toList(),
                  ),
            child: _progressRow(
              'DISK',
              metrics.diskPercent,
              const Color(0xFF722ED1),
              detail:
                  '${_formatBytes(metrics.diskUsed)}/${_formatBytes(metrics.diskTotal)}',
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                '↓ ${_formatBytes(metrics.rxRate)}/s · ${_formatBytes(metrics.rxTotal)}',
                style: const TextStyle(color: AntdTokens.success, fontSize: 10),
              ),
            ),
            Expanded(
              child: Text(
                '↑ ${_formatBytes(metrics.txRate)}/s · ${_formatBytes(metrics.txTotal)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AntdTokens.primary, fontSize: 10),
              ),
            ),
          ]),
          if (limit > 0) ...[
            const SizedBox(height: 6),
            _progressRow(
              _text(state, '流量', 'Traffic'),
              trafficPercent,
              trafficPercent >= host.notifyTrafficThreshold
                  ? AntdTokens.error
                  : AntdTokens.primary,
              detail: '${_formatBytes(trafficUsed)}/${_formatBytes(limit)}',
            ),
            const SizedBox(height: 2),
            Text(
              '${_text(state, '下次重置', 'Next reset')}: ${_nextResetDate(host.netResetDay)}',
              style: const TextStyle(fontSize: 9, color: AntdTokens.primary),
            ),
          ],
          if (host.expirationDate != null || host.billingAmount > 0) ...[
            const SizedBox(height: 5),
            Text(
              '${_text(state, '到期', 'Expires')}: ${host.expirationDate?.split('T').first ?? '-'}'
              ' · ${host.currency}${host.billingAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 10,
                color: _daysUntil(host.expirationDate) <= 7
                    ? AntdTokens.warning
                    : AntdTokens.secondaryTextColor(context),
              ),
            ),
          ],
          if (updateStatus.isNotEmpty) ...[
            const SizedBox(height: 4),
            AntdTag(preset: AntdTagPreset.processing, label: updateStatus),
          ],
        ],
      ),
    );

    final flag = _flagColor(host.flag);
    if (flag == null) return card;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: flag, width: 3)),
      ),
      child: card,
    );
  }

  List<AntdButton> _cardActions(
    AppState state,
    Host host,
    bool outdated,
  ) {
    return [
      if (outdated)
        AntdButton(
          type: AntdButtonType.text,
          icon: Icons.system_update_alt,
          size: AntdSize.small,
          onPressed: () async {
            final ok = await state.updateMonitorAgent(host.id.toString());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? _text(state, '已触发 Agent 更新', 'Agent update started')
                    : _text(state, 'Agent 更新失败', 'Agent update failed')),
                backgroundColor: ok ? AntdTokens.success : AntdTokens.error,
              ));
            }
          },
        ),
      AntdButton(
        type: AntdButtonType.text,
        icon: Icons.show_chart,
        size: AntdSize.small,
        onPressed: () => _openNetwork(host, 'connectivity'),
      ),
      if (host.hostType != 'monitor_only')
        AntdButton(
          type: AntdButtonType.text,
          icon: Icons.code,
          size: AntdSize.small,
          onPressed: () => state.addTerminal(host),
        ),
      AntdButton(
        type: AntdButtonType.text,
        icon: Icons.history,
        size: AntdSize.small,
        onPressed: () => _showStatusLogs(state, host),
      ),
      AntdButton(
        type: AntdButtonType.text,
        icon: Icons.settings,
        size: AntdSize.small,
        onPressed: () => _openNetwork(host, 'config'),
      ),
    ];
  }

  Widget _buildActions(AppState state, Host host) => Wrap(
        spacing: 2,
        children: _cardActions(
          state,
          host,
          _isAgentOutdated(state, host, _info(state, host)),
        ),
      );

  void _openNetwork(Host host, String tab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NetworkDetailScreen(hostId: host.id, initialTab: tab),
      ),
    );
  }

  void _showReorderDialog(AppState state, List<Host> hosts) {
    final ordered = List<Host>.from(hosts);
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AntdModal(
          title: Text(_text(state, '监控主机排序', 'Reorder monitored hosts')),
          width: 480,
          okText: _text(state, '保存排序', 'Save order'),
          cancelText: _text(state, '取消', 'Cancel'),
          onOk: () async {
            final ok = await state.reorderHosts(
              ordered.map((host) => host.id).toList(),
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ok
                  ? _text(state, '排序已更新', 'Order updated')
                  : _text(state, '排序保存失败', 'Failed to save order')),
              backgroundColor: ok ? AntdTokens.success : AntdTokens.error,
            ));
          },
          child: SizedBox(
            height: 360,
            child: ReorderableListView.builder(
              itemCount: ordered.length,
              onReorder: (oldIndex, newIndex) {
                setDialogState(() {
                  if (oldIndex < newIndex) newIndex--;
                  final host = ordered.removeAt(oldIndex);
                  ordered.insert(newIndex, host);
                });
              },
              itemBuilder: (_, index) {
                final host = ordered[index];
                return ListTile(
                  key: ValueKey(host.id),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(host.name),
                  subtitle: Text(host.host),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressRow(
    String label,
    double percent,
    Color color, {
    String? detail,
  }) {
    return Row(children: [
      SizedBox(
        width: 42,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      ),
      Expanded(
        child: AntdProgress(
          percent: percent.clamp(0, 100).toDouble(),
          color: color,
          strokeWidth: 4,
        ),
      ),
      if (detail != null) ...[
        const SizedBox(width: 4),
        Text(detail, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    ]);
  }

  double _trafficUsed(Host host, _MonitorMetrics metrics) {
    final measured = switch (host.netTrafficCounterMode) {
      'rx' => metrics.rxTotal,
      'tx' => metrics.txTotal,
      _ => metrics.rxTotal + metrics.txTotal,
    };
    return measured + host.netTrafficUsedAdjustment;
  }

  void _showTrafficResetLogs(AppState state) {
    showDialog<void>(
      context: context,
      builder: (_) => _PagedMonitorLogsDialog(
        api: state,
        title: _text(state, '流量重置日志', 'Traffic reset logs'),
        endpoint: '/api/monitor/traffic-reset-logs',
        emptyText: _text(state, '暂无重置日志', 'No reset logs'),
        itemBuilder: (context, log) {
          final time = _formatDateTime(log['created_at']);
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, color: AntdTokens.primary),
            title: Text((log['host_name'] ?? '-').toString()),
            subtitle: Text('${log['reset_type'] ?? '-'} · $time'),
          );
        },
      ),
    );
  }

  void _showStatusLogs(AppState state, Host host) {
    showDialog<void>(
      context: context,
      builder: (_) => _PagedMonitorLogsDialog(
        api: state,
        title: '${host.name} - ${_text(state, '状态历史', 'Status history')}',
        endpoint: '/api/ssh-hosts/${host.id}/monitor/logs',
        emptyText: _text(state, '暂无状态日志', 'No status logs'),
        itemBuilder: (context, log) {
          final status = log['status']?.toString() ?? '-';
          final online = status.toLowerCase().contains('online') ||
              status.toLowerCase().contains('up');
          return ListTile(
            dense: true,
            leading: Icon(
              online ? Icons.check_circle_outline : Icons.error_outline,
              color: online ? AntdTokens.success : AntdTokens.error,
            ),
            title: Text(status),
            subtitle: Text(_formatDateTime(log['created_at'])),
          );
        },
      ),
    );
  }

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String _formatBytes(num bytes) {
    final value = bytes.toDouble();
    if (value <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    final index = (log(value) / log(1024)).floor().clamp(0, units.length - 1);
    return '${(value / pow(1024, index)).toStringAsFixed(1)} ${units[index]}';
  }

  static String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  static int _daysUntil(String? value) {
    if (value == null || value.isEmpty) return 999;
    return DateTime.tryParse(value)?.difference(DateTime.now()).inDays ?? 999;
  }

  static String _nextResetDate(int day) {
    final now = DateTime.now();
    final resetDay = day <= 0 ? 1 : day;
    var year = now.year;
    var month = now.month;
    var candidate =
        DateTime(year, month, min(resetDay, _daysInMonth(year, month)));
    if (!candidate.isAfter(now)) {
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
      candidate =
          DateTime(year, month, min(resetDay, _daysInMonth(year, month)));
    }
    return '${candidate.year}-${candidate.month.toString().padLeft(2, '0')}-${candidate.day.toString().padLeft(2, '0')}';
  }

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  static Color? _flagColor(String? flag) => switch (flag) {
        'red' => const Color(0xFFFF4D4F),
        'orange' => const Color(0xFFFF7A45),
        'yellow' => const Color(0xFFFAAD14),
        'green' => const Color(0xFF52C41A),
        'blue' => const Color(0xFF1890FF),
        'purple' => const Color(0xFF722ED1),
        _ => null,
      };

  static String _formatDateTime(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '-';
    return parsed.toLocal().toString().split('.').first;
  }
}

class _MonitorMetrics {
  _MonitorMetrics(this.info);

  final Map<String, dynamic> info;

  bool get online =>
      info.isNotEmpty &&
      info['_offline'] != true &&
      info['status']?.toString().toLowerCase() != 'offline';
  double get cpu => _MonitorTabState._number(info['cpu']);
  int get cpuCount => _MonitorTabState._number(info['cpu_count']).round();
  String get cpuModel => info['cpu_model']?.toString() ?? '';
  double get cpuMhz => _MonitorTabState._number(info['cpu_mhz']);
  int get uptime => _MonitorTabState._number(info['uptime']).round();
  double get memUsed => _MonitorTabState._number(info['mem_used']);
  double get memTotal => max(_MonitorTabState._number(info['mem_total']), 1);
  double get memoryPercent => memUsed / memTotal * 100;
  List<Map<String, dynamic>> get disks => (info['disks'] is List)
      ? (info['disks'] as List)
          .whereType<Map>()
          .map((disk) => Map<String, dynamic>.from(disk))
          .toList()
      : [];
  double get diskUsed => disks.isEmpty
      ? _MonitorTabState._number(info['disk_used'])
      : disks.fold(
          0, (sum, disk) => sum + _MonitorTabState._number(disk['used']));
  double get diskTotal => max(
        disks.isEmpty
            ? _MonitorTabState._number(info['disk_total'])
            : disks.fold(
                0,
                (sum, disk) => sum + _MonitorTabState._number(disk['total']),
              ),
        1,
      );
  double get diskPercent => diskUsed / diskTotal * 100;
  double get rxRate => _MonitorTabState._number(info['net_rx_rate']);
  double get txRate => _MonitorTabState._number(info['net_tx_rate']);
  double get rxTotal => _MonitorTabState._number(info['net_monthly_rx']);
  double get txTotal => _MonitorTabState._number(info['net_monthly_tx']);
}

class _PagedMonitorLogsDialog extends StatefulWidget {
  const _PagedMonitorLogsDialog({
    required this.api,
    required this.title,
    required this.endpoint,
    required this.emptyText,
    required this.itemBuilder,
  });

  final AppState api;
  final String title;
  final String endpoint;
  final String emptyText;
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;

  @override
  State<_PagedMonitorLogsDialog> createState() =>
      _PagedMonitorLogsDialogState();
}

class _PagedMonitorLogsDialogState extends State<_PagedMonitorLogsDialog> {
  static const int _pageSize = 20;
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int? page]) async {
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final separator = widget.endpoint.contains('?') ? '&' : '?';
      final result = await widget.api.apiService.get(
        '${widget.endpoint}${separator}page=$nextPage&page_size=$_pageSize',
      );
      if (!mounted) return;
      final data = result is Map ? result['data'] : result;
      setState(() {
        _page = nextPage;
        _logs = data is List
            ? data
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
        _total = result is Map
            ? (result['total'] as num?)?.toInt() ?? _logs.length
            : _logs.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AntdModal(
      title: Text(widget.title),
      width: 620,
      showFooter: false,
      child: SizedBox(
        height: 430,
        width: double.maxFinite,
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: AntdSpin(tip: 'Loading...'))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AntdTokens.error),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            AntdButton(
                              icon: Icons.refresh,
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _logs.isEmpty
                        ? AntdEmpty(description: widget.emptyText)
                        : ListView.separated(
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: AntdTokens.borderSecondaryColor(context),
                            ),
                            itemBuilder: (context, index) =>
                                widget.itemBuilder(context, _logs[index]),
                          ),
          ),
          AntdPagination(
            current: _page,
            total: _total,
            pageSize: _pageSize,
            pageSizeOptions: const [_pageSize],
            showTotal: true,
            onChange: _load,
          ),
        ]),
      ),
    );
  }
}
