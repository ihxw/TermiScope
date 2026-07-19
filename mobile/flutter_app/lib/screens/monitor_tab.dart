import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/antd_tokens.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
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

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!state.monitorConnected)
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
            child: AntdAlert(
              type: AntdAlertType.error,
              message: _text(
                state,
                '监控实时连接已断开',
                'Monitor connection lost',
              ),
              description: _text(
                state,
                '正在自动重连...',
                'Automatically reconnecting...',
              ),
              showIcon: true,
            ),
          ),
        _buildToolbar(state, hosts, onlineCount, outdatedCount),
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

  Widget _buildToolbar(
    AppState state,
    List<Host> hosts,
    int onlineCount,
    int outdatedCount,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
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
          Text(
            '${_text(state, '总计', 'Total')}: ${hosts.length}',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8C8C8C),
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            width: 1,
            height: 14,
            color: AntdTokens.borderSecondaryColor(context),
          ),
          Text(
            '${_text(state, '在线', 'Online')}: $onlineCount',
            style: const TextStyle(fontSize: 13, color: AntdTokens.success),
          ),
          AntdButton(
            size: AntdSize.small,
            icon: Icons.history,
            onPressed: () => _showTrafficResetLogs(state),
            child: Text(_text(state, '重置日志', 'Reset logs')),
          ),
          AntdButton(
            size: AntdSize.small,
            icon: Icons.swap_vert,
            onPressed: () => _showReorderDialog(state, hosts),
          ),
          if (state.profile?.role == 'admin')
            AntdButton(
              size: AntdSize.small,
              icon: Icons.app_registration,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MonitorTemplatesScreen(),
                ),
              ),
              child: Text(_text(state, '模板管理', 'Templates')),
            ),
          if (outdatedCount > 0)
            AntdButton(
              size: AntdSize.small,
              type: AntdButtonType.primary,
              icon: Icons.sync,
              loading: _batchUpdating,
              onPressed: _batchUpdating ? null : () => _batchUpdate(state, hosts),
              child: Text(
                '${_text(state, '批量更新', 'Batch update')} ($outdatedCount)',
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _info(AppState state, Host host) {
    final raw = state.monitorData[host.id.toString()];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static int _cardColumns(double width) {
    if (width >= 1200) return 5;
    if (width >= 768) return 3;
    if (width >= 480) return 2;
    return 1;
  }

  Widget _buildCardGrid(
    BuildContext context,
    AppState state,
    List<Host> hosts,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = _cardColumns(constraints.maxWidth);
      final rows = <List<Host>>[];
      for (var i = 0; i < hosts.length; i += cols) {
        rows.add(hosts.sublist(i, min(i + cols, hosts.length)));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < rows.length; row++) ...[
              if (row > 0) const SizedBox(height: 5),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final host in rows[row])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: rows[row].last == host ? 0 : 5,
                          ),
                          child: SizedBox(
                            key: ValueKey('monitor-card-${host.id}'),
                            child: _buildMonitorCard(state, host),
                          ),
                        ),
                      ),
                    for (var i = rows[row].length; i < cols; i++)
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ],
        ),
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
          final outdated = _isAgentOutdated(state, host, info);
          final updateStatus = info['agent_update_status']?.toString() ?? '';
          final os = (info['os'] ?? 'linux').toString().toLowerCase();
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(children: [
              Icon(_osIcon(os), size: 18),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(host.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                  if (updateStatus.isNotEmpty) ...[const SizedBox(width: 8), AntdTag(preset: AntdTagPreset.processing, label: updateStatus)]
                  else if (outdated) ...[const SizedBox(width: 8), AntdButton(size: AntdSize.small, type: AntdButtonType.primary, onPressed: () async { try { await state.updateMonitorAgent(host.id.toString()); } catch (_) {} }, child: Text(_text(state, '立即更新', 'Update now'), style: const TextStyle(fontSize: 10)))]
                ]),
                Text(info['hostname']?.toString() ?? host.host, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
              ])),
            ]),
          );
        },
      ),
      AntdTableColumn(
        title: _text(state, '状态', 'Status'),
        width: 100,
        cell: (_, host, __) {
          final online = state.monitorConnected && _MonitorMetrics(_info(state, host)).online;
          final m = _MonitorMetrics(_info(state, host));
          return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AntdTag(preset: online ? AntdTagPreset.success : AntdTagPreset.error, label: online ? 'ONLINE' : 'OFFLINE'),
            if (online) Text(_formatUptime(m.uptime), style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
          ]);
        },
      ),
      _pcBarCol(state, 'CPU', 100, (info, m) => (pct: m.cpu, label: '${m.cpu.toStringAsFixed(1)}%', detail: m.cpuCount > 0 ? '${m.cpuCount}C ${m.cpuModel}' : null)),
      _pcBarCol(state, 'RAM', 145, (info, m) => (pct: m.memoryPercent, label: '${_pct(m.memUsed, m.memTotal)}%', detail: '${_formatBytes(m.memUsed)} / ${_formatBytes(m.memTotal)}')),
      _tblDiskCol(state),
      _tblNetCol(state),
      _tblTrafficCol(state),
      AntdTableColumn(
        title: _text(state, '财务', 'Finance'),
        width: 180,
        cell: (_, host, __) {
          if (host.expirationDate == null && host.billingAmount <= 0) return const Center(child: Text('-', style: TextStyle(color: Colors.grey, fontSize: 11)));
          final daysLeft = _daysUntil(host.expirationDate);
          final expColor = daysLeft < 0 ? AntdTokens.error : (daysLeft <= 7 ? AntdTokens.warning : null);
          return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (host.expirationDate != null) Text.rich(TextSpan(children: [
              TextSpan(text: host.expirationDate!.split('T').first, style: TextStyle(fontSize: 11, color: expColor)),
              TextSpan(text: ' (${_text(state, '剩余 $daysLeft 天', '${daysLeft}d left')})', style: TextStyle(fontSize: 10, color: expColor ?? const Color(0xFF8C8C8C))),
            ])),
            if ((host.billingPeriod ?? '').isNotEmpty || host.billingAmount > 0) Text('${_billingLabel(state, host.billingPeriod ?? '')}:${_currencySymbol(host.currency ?? '')}${host.billingAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
          ]);
        },
      ),
      AntdTableColumn(
        title: _text(state, '操作', 'Actions'),
        width: 160,
        cell: (_, host, __) {
          final isMonitorOnly = host.hostType == 'monitor_only';
          return Row(mainAxisSize: MainAxisSize.min, children: [
            _iconBtn(Icons.show_chart, '', () => _openNetwork(host, 'connectivity')),
            _iconBtn(Icons.code, '', isMonitorOnly ? null : () => state.addTerminal(host)),
            _iconBtn(Icons.history, '', () => _showStatusLogs(state, host)),
            _iconBtn(Icons.settings, '', () => _openNetwork(host, 'config')),
          ]);
        },
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          color: AntdTokens.containerColor(context),
          border: Border.all(color: AntdTokens.borderSecondaryColor(context)),
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: AntdTable<Host>(rowKey: (h) => h.id.toString(), data: hosts, columns: columns, rowHeight: 56),
      ),
    );
  }

  AntdTableColumn<Host> _pcBarCol(AppState state, String title, double w,
    ({double pct, String label, String? detail}) Function(Map<String, dynamic>, _MonitorMetrics) fn) {
    return AntdTableColumn(title: title, width: w, cell: (_, host, __) {
      final info = _info(state, host);
      final m = _MonitorMetrics(info);
      final r = fn(info, m);
      return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(r.label, style: const TextStyle(fontSize: 12)),
          if (r.detail != null) Flexible(child: Text(' ${r.detail}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C)))),
        ]),
        const SizedBox(height: 2),
        AntdProgress(percent: r.pct.clamp(0, 100).toDouble(), color: _progressColor(r.pct), strokeWidth: 4, showInfo: false),
      ]);
    });
  }

  AntdTableColumn<Host> _tblDiskCol(AppState state) {
    return AntdTableColumn(title: _text(state, '磁盘', 'Disk'), width: 145, cell: (_, host, __) {
      final m = _MonitorMetrics(_info(state, host));
      final pct = m.diskPercent;
      Widget content = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${_formatBytes(m.diskUsed)} / ${_formatBytes(m.diskTotal)}', style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
          const Spacer(),
          Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: _progressColor(pct))),
        ]),
        const SizedBox(height: 2),
        AntdProgress(percent: pct.clamp(0, 100).toDouble(), color: _progressColor(pct), strokeWidth: 4, showInfo: false),
      ]);
      if (m.disks.isEmpty) return content;
      return AntdPopover(width: 280, title: Text(_text(state, '磁盘明细', 'Disk details')), content: Column(mainAxisSize: MainAxisSize.min, children: m.disks.map((disk) {
        final u = _number(disk['used']); final t = max(_number(disk['total']), 1);
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: _sectionRow(
          (disk['mount_point'] ?? disk['mount'] ?? disk['path'] ?? '-').toString(), '${_pct(u, t)}%',
          subtitle: '${_formatBytes(u)} / ${_formatBytes(t)}', percent: u/t*100,
        ));
      }).toList()), child: content);
    });
  }

  AntdTableColumn<Host> _tblNetCol(AppState state) {
    return AntdTableColumn(title: _text(state, '网络', 'Network'), width: 140, cell: (_, host, __) {
      final m = _MonitorMetrics(_info(state, host));
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          const Icon(Icons.arrow_downward, size: 12, color: AntdTokens.success),
          Expanded(child: Text(' ${_formatBytes(m.rxRate)}/s', style: const TextStyle(fontSize: 12, color: AntdTokens.success))),
          Text(_formatBytes(m.rxTotal), style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
        ]),
        Row(children: [
          const Icon(Icons.arrow_upward, size: 12, color: AntdTokens.primary),
          Expanded(child: Text(' ${_formatBytes(m.txRate)}/s', style: const TextStyle(fontSize: 12, color: AntdTokens.primary))),
          Text(_formatBytes(m.txTotal), style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
        ]),
      ]);
    });
  }

  AntdTableColumn<Host> _tblTrafficCol(AppState state) {
    return AntdTableColumn(title: _text(state, '流量', 'Traffic'), width: 140, cell: (_, host, __) {
      final m = _MonitorMetrics(_info(state, host));
      final limit = host.netTrafficLimit ?? 0;
      if (limit <= 0) return const Center(child: Text('-', style: TextStyle(color: Colors.grey, fontSize: 11)));
      final used = _trafficUsed(host, m);
      final pct = (used / limit * 100).clamp(0, 100).toDouble();
      return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${_trafficLabel(state, host.netTrafficCounterMode ?? '')} · ${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
          const Spacer(),
          Text(_formatBytes(used), style: const TextStyle(fontSize: 10)),
        ]),
        const SizedBox(height: 2),
        AntdProgress(percent: pct, color: _progressColor(pct), strokeWidth: 6, showInfo: false),
        if ((host.netResetDay ?? 0) > 0) Text('${_text(state, '下次重置', 'Next reset')}: ${_nextResetDate(host.netResetDay ?? 1)}', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
      ]);
    });
  }

  Widget _buildMonitorCard(AppState state, Host host) {
    final info = _info(state, host);
    final metrics = _MonitorMetrics(info);
    final online = state.monitorConnected && metrics.online;
    final version = (info['agent_version'] ?? host.agentVersion).toString();
    final updateStatus = info['agent_update_status']?.toString() ?? '';
    final outdated = _isAgentOutdated(state, host, info);
    final os = (info['os'] ?? 'linux').toString().toLowerCase();
    final trafficUsed = _trafficUsed(host, metrics);
    final limit = host.netTrafficLimit ?? 0;
    final trafficPercent =
        limit > 0 ? (trafficUsed / limit * 100).clamp(0, 100).toDouble() : 0.0;
    final isMonitorOnly = host.hostType == 'monitor_only';
    final flagBorder = _flagColor(host.flag) != null
        ? Border(left: BorderSide(color: _flagColor(host.flag)!, width: 5))
        : null;

    Widget card = AntdCard(
      padding: const EdgeInsets.all(12),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_osIcon(os), size: 20, color: AntdTokens.textColor(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(host.name, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  info['hostname']?.toString() ?? host.host,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C), fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      extra: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconBtn(Icons.show_chart, _text(state, '网络详情', 'Network'), () => _openNetwork(host, 'connectivity')),
        _iconBtn(Icons.code, isMonitorOnly ? _text(state, '仅监控', 'Monitor only') : _text(state, '终端', 'Terminal'), isMonitorOnly ? null : () => state.addTerminal(host)),
        _iconBtn(Icons.history, _text(state, '历史', 'History'), () => _showStatusLogs(state, host)),
        _iconBtn(Icons.settings, _text(state, '设置', 'Settings'), () => _openNetwork(host, 'config')),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // OS · Uptime · Agent
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
          Icon(_osIcon(os), size: 14, color: const Color(0xFF8C8C8C)),
          Text(_osLabel(os), style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
          const Text('|', style: TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
          Text('${_text(state, '运行时间', 'Uptime')}: ${_formatUptime(metrics.uptime)}', style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
          if (version.isNotEmpty) ...[
            const Text('|', style: TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
            Text('Agent: v$version', style: const TextStyle(fontSize: 12, color: const Color(0xFF8C8C8C))),
            if (updateStatus.isNotEmpty)
              AntdTag(preset: AntdTagPreset.processing, label: updateStatus)
            else if (outdated)
              GestureDetector(
                onTap: () async { try { await state.updateMonitorAgent(host.id.toString()); } catch (_) {} },
                child: AntdTag(preset: AntdTagPreset.warning, label: _text(state, '更新', 'Update')),
              ),
          ],
        ]),
        const SizedBox(height: 6),
        // CPU
        _sectionRow(
          _text(state, 'CPU', 'CPU'),
          '${metrics.cpu.toStringAsFixed(1)}%',
          subtitle: metrics.cpuCount > 0
              ? '${metrics.cpuCount}C ${metrics.cpuModel}${metrics.cpuMhz > 0 ? ' @ ${_formatMhz(metrics.cpuMhz)}' : ''}'
              : null,
          percent: metrics.cpu,
        ),
        const SizedBox(height: 6),
        // RAM
        _sectionRow(
          _text(state, 'RAM', 'RAM'),
          '${_pct(metrics.memUsed, metrics.memTotal)}%',
          subtitle: '${_formatBytes(metrics.memUsed)} / ${_formatBytes(metrics.memTotal)}',
          percent: metrics.memoryPercent,
        ),
        const SizedBox(height: 6),
        // Disk
        if (metrics.disks.isNotEmpty)
          AntdPopover(
            width: 280,
            title: Text(_text(state, '磁盘明细', 'Disk details')),
            content: Column(mainAxisSize: MainAxisSize.min, children: metrics.disks.map((disk) {
              final u = _number(disk['used']);
              final t = max(_number(disk['total']), 1);
              return Padding(padding: const EdgeInsets.only(bottom: 8), child: _sectionRow(
                (disk['mount_point'] ?? disk['mount'] ?? disk['path'] ?? '-').toString(),
                '${_pct(u, t)}%',
                subtitle: '${_formatBytes(u)} / ${_formatBytes(t)}',
                percent: u / t * 100,
              ));
            }).toList()),
            child: _sectionRow(
              _text(state, '磁盘', 'Disk'),
              '${metrics.diskPercent.toStringAsFixed(0)}%',
              subtitle: '${_formatBytes(metrics.diskUsed)} / ${_formatBytes(metrics.diskTotal)}',
              percent: metrics.diskPercent,
            ),
          )
        else
          _sectionRow(
            _text(state, '磁盘', 'Disk'),
            '${metrics.diskPercent.toStringAsFixed(0)}%',
            subtitle: '${_formatBytes(metrics.diskUsed)} / ${_formatBytes(metrics.diskTotal)}',
            percent: metrics.diskPercent,
          ),
        const SizedBox(height: 6),
        // Network
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('↓ ${_formatBytes(metrics.rxRate)}/s', style: const TextStyle(color: AntdTokens.success, fontSize: 12)),
            Text('${_text(state, '总计', 'Total')}: ${_formatBytes(metrics.rxTotal)}', style: const TextStyle(color: const Color(0xFF8C8C8C), fontSize: 11)),
          ])),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text('↑ ${_formatBytes(metrics.txRate)}/s', style: const TextStyle(color: AntdTokens.primary, fontSize: 12)),
            Text('${_text(state, '总计', 'Total')}: ${_formatBytes(metrics.txTotal)}', style: const TextStyle(color: const Color(0xFF8C8C8C), fontSize: 11)),
          ])),
        ]),
        // Traffic
        if (limit > 0) ...[
          const SizedBox(height: 6),
          Container(width: double.infinity, height: 1, color: AntdTokens.borderSecondaryColor(context)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              flex: 3,
              child: Text('${_text(state, '流量', 'Usage')} · ${_trafficLabel(state, host.netTrafficCounterMode ?? '')} (${trafficPercent.toStringAsFixed(0)}%)',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text('${_formatBytes(trafficUsed)} / ${_formatBytes(limit)}',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 2),
          AntdProgress(percent: trafficPercent.clamp(0, 100).toDouble(), color: _progressColor(trafficPercent), strokeWidth: 6, showInfo: false),
          if ((host.netResetDay ?? 0) > 0) ...[
            const SizedBox(height: 2),
            Text('${_text(state, '下次重置', 'Next reset')}: ${_nextResetDate(host.netResetDay ?? 1)}', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          ],
        ],
        // Financial
        if (host.expirationDate != null || host.billingAmount > 0) ...[
          const SizedBox(height: 6),
          Container(width: double.infinity, height: 1, color: AntdTokens.borderSecondaryColor(context)),
          const SizedBox(height: 6),
          _financialRow(state, host),
        ],
      ]),
    );

    if (flagBorder != null) {
      card = Container(decoration: BoxDecoration(border: flagBorder), child: card);
    }
    if (!online) {
      card = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: Opacity(opacity: 0.7, child: card),
      );
    }
    return card;
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return AntdButton(type: AntdButtonType.text, icon: icon, size: AntdSize.small, onPressed: onPressed);
  }

  Widget _sectionRow(String label, String pctStr, {String? subtitle, required double percent}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (subtitle != null) Flexible(child: Text(' $subtitle', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: const Color(0xFF8C8C8C)))),
        const Spacer(),
        Text(pctStr, style: TextStyle(fontSize: 12, color: _progressColor(percent))),
      ]),
      const SizedBox(height: 2),
      AntdProgress(percent: percent.clamp(0, 100).toDouble(), color: _progressColor(percent), strokeWidth: 6, showInfo: false),
    ]);
  }

  Widget _financialRow(AppState state, Host host) {
    final daysLeft = _daysUntil(host.expirationDate);
    final expColor = daysLeft < 0 ? AntdTokens.error : (daysLeft <= 7 ? AntdTokens.warning : null);
    final hasBilling = (host.billingPeriod ?? '').isNotEmpty || host.billingAmount > 0;
    return Row(children: [
      const Icon(Icons.info_outline, size: 14, color: const Color(0xFF8C8C8C)),
      const SizedBox(width: 4),
      if (host.expirationDate != null)
        Expanded(
          flex: 3,
          child: Text(
              '${_text(state, '到期', 'Expires')}: ${host.expirationDate!.split('T').first} '
              '(${_text(state, '剩余 $daysLeft 天', '${daysLeft}d left')})',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: expColor ?? const Color(0xFF8C8C8C))),
        ),
      if (host.expirationDate != null && hasBilling) const SizedBox(width: 4),
      if (hasBilling)
        Expanded(
          flex: 2,
          child: Text('${_billingLabel(state, host.billingPeriod ?? '')}:${_currencySymbol(host.currency ?? '')}${host.billingAmount.toStringAsFixed(2)}',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10, color: const Color(0xFF8C8C8C))),
        ),
    ]);
  }

  Color _progressColor(double pct) {
    if (pct >= 90) return AntdTokens.error;
    if (pct >= 80) return AntdTokens.warning;
    return AntdTokens.primary;
  }

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

  String _trafficLabel(AppState state, String mode) {
    switch (mode) {
      case 'rx': return _text(state, '下载', 'RX');
      case 'tx': return _text(state, '上传', 'TX');
      default: return _text(state, '总计', 'Total');
    }
  }

  IconData _osIcon(String os) {
    os = os.toLowerCase();
    if (os.contains('win')) return Icons.info_outline;
    return Icons.desktop_mac_outlined;
  }

  String _osLabel(String os) {
    os = os.toLowerCase();
    if (os.contains('win')) return 'Windows';
    if (os.contains('darwin') || os.contains('mac')) return 'macOS';
    return os.isEmpty ? 'Linux' : os;
  }

  static String _formatMhz(double mhz) {
    if (mhz >= 1000) return '${(mhz / 1000).toStringAsFixed(2)} GHz';
    return '${mhz.toStringAsFixed(0)} MHz';
  }

  static String _pct(num used, num total) {
    if (total <= 0) return '0';
    return ((used / total) * 100).toStringAsFixed(0);
  }

  String _billingLabel(AppState state, String period) {
    switch (period.toLowerCase()) {
      case 'monthly': return _text(state, '月付', 'Monthly');
      case 'quarterly': return _text(state, '季付', 'Quarterly');
      case 'semiannually': return _text(state, '半年付', 'Semi-annual');
      case 'annually': return _text(state, '年付', 'Annual');
      default: return period;
    }
  }

  static String _currencySymbol(String? currency) => switch (currency) {
    'USD' => r'$', 'EUR' => '\u20AC', 'GBP' => '\u00A3', 'JPY' => '\u00A5',
    _ => '\u00A5',
  };

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
