import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';
import 'host_edit_dialog.dart';

class HostManagementScreen extends StatefulWidget {
  const HostManagementScreen({super.key});
  @override
  State<HostManagementScreen> createState() => _HostManagementScreenState();
}

class _HostManagementScreenState extends State<HostManagementScreen> {
  bool _isLoading = false;
  String _searchText = '';
  String _quickFilter = 'all';
  bool _showDeleted = false;
  bool _batchLoading = false;
  final Set<String> _selectedHostIds = {};
  final Set<int> _checkingHostIds = {};
  List<Map<String, dynamic>> _orphanAgents = [];
  bool _orphanBannerDismissed = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHosts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHosts() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    await state.fetchHosts(includeDeleted: _showDeleted);
    await _loadOrphanAgents(state);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _selectedHostIds.removeWhere(
        (id) => !state.hosts.any((host) => host.id.toString() == id),
      );
    });
    await _refreshConnectionStatus(state);
  }

  Future<void> _loadOrphanAgents(AppState state) async {
    if (state.profile == null) await state.fetchProfile();
    if (state.profile?.role != 'admin') return;
    try {
      final result = await state.apiService.get('/api/monitor/orphan-agents');
      final raw = result is Map ? result['agents'] : result;
      if (mounted) {
        setState(() {
          _orphanAgents = raw is List
              ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
              : [];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _orphanAgents = []);
    }
  }

  void _add() {
    showDialog(context: context, builder: (_) => const HostEditDialog())
        .then((_) => _loadHosts());
  }

  void _edit(Host h) {
    showDialog(
      context: context,
      builder: (_) => HostEditDialog(host: h.toJson()),
    ).then((_) => _loadHosts());
  }

  void _del(AppState st, Host h) {
    showDialog(
        context: context,
        builder: (_) => AntdModal(
              title:
                  Text(Translation.getText(st.locale, 'common.confirmDelete')),
              width: 400,
              danger: true,
              okText: Translation.getText(st.locale, 'common.confirm'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                await st.deleteHost(h.id.toString());
                _loadHosts();
              },
              child: Text(
                '${Translation.getText(st.locale, 'host.deleteConfirm')}\n${h.name}',
              ),
            ));
  }

  void _permanentlyDelete(AppState st, Host h) {
    showDialog(
      context: context,
      builder: (_) => AntdModal(
        title: Text(Translation.getText(st.locale, 'host.permanentDelete')),
        width: 420,
        danger: true,
        okText: Translation.getText(st.locale, 'host.permanentDelete'),
        cancelText: Translation.getText(st.locale, 'common.cancel'),
        onOk: () async {
          final ok = await st.permanentlyDeleteHost(h.id.toString());
          if (!mounted) return;
          _showResult(
            ok,
            Translation.getText(
                st.locale,
                ok
                    ? 'host.permanentDeleteSuccess'
                    : 'host.permanentDeleteFailed'),
          );
          await _loadHosts();
        },
        child: Text(
          '${Translation.getText(st.locale, 'host.permanentDeleteConfirm')}\n${h.name}',
        ),
      ),
    );
  }

  Future<void> _refreshConnectionStatus(AppState state) async {
    final targets = state.hosts.where(
      (host) => host.deletedAt == null && host.hostType != 'monitor_only',
    );
    await Future.wait(targets.map((host) async {
      if (_checkingHostIds.contains(host.id)) return;
      _checkingHostIds.add(host.id);
      try {
        await state.testHostConnection(host.id.toString());
      } finally {
        _checkingHostIds.remove(host.id);
      }
    }));
    if (mounted) setState(() {});
  }

  Future<void> _runBatch(
    AppState state,
    Future<Map<String, int>> Function(Iterable<int>) action,
    String actionName,
  ) async {
    final ids = _selectedHostIds
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => state.hosts.any((host) =>
            host.id == id &&
            host.deletedAt == null &&
            host.hostType != 'monitor_only'))
        .toList();
    if (ids.isEmpty) return;
    setState(() => _batchLoading = true);
    final result = await action(ids);
    if (!mounted) return;
    setState(() {
      _batchLoading = false;
      _selectedHostIds.clear();
    });
    _showResult(
      result['failed'] == 0,
      '$actionName: ${result['success']} / ${ids.length}',
    );
    await _loadHosts();
  }

  Future<void> _runBatchSetting(
    AppState state,
    String field,
    bool value,
  ) async {
    final ids = _selectedHostIds.map(int.tryParse).whereType<int>().toList();
    if (ids.isEmpty) return;
    setState(() => _batchLoading = true);
    final result = await state.updateHostsSetting(ids, {field: value});
    if (!mounted) return;
    setState(() => _batchLoading = false);
    _showResult(
      result['failed'] == 0,
      '${value ? 'Enable' : 'Disable'}: ${result['success']} / ${ids.length}',
    );
  }

  void _showOrphanAgents(AppState state) {
    showDialog<void>(
      context: context,
      builder: (_) => AntdModal(
        title: Text(_text(state, '孤立 Agent', 'Orphan agents')),
        width: 560,
        showFooter: false,
        child: SizedBox(
          height: 320,
          child: ListView.separated(
            itemCount: _orphanAgents.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: AntdTokens.borderSecondaryColor(context),
            ),
            itemBuilder: (_, index) {
              final agent = _orphanAgents[index];
              final names = (agent['hostnames'] as List?)?.join(', ') ?? '-';
              final ips = (agent['client_ips'] as List?)?.join(', ') ?? '-';
              return ListTile(
                leading:
                    const Icon(Icons.warning_amber, color: AntdTokens.warning),
                title: Text('Host ID ${agent['host_id']} · $names'),
                subtitle: Text('$ips · ${agent['last_seen_at'] ?? '-'}'),
              );
            },
          ),
        ),
      ),
    );
  }

  String _text(AppState state, String zh, String en) =>
      state.locale == 'zh' ? zh : en;

  void _showResult(bool success, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: success ? AntdTokens.success : AntdTokens.warning,
    ));
  }

  void _test(AppState st, Host h) async {
    final r = await st.testHostConnection(h.id.toString());
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message'] ?? ''),
          backgroundColor:
              r['success'] == true ? AntdTokens.success : AntdTokens.error,
          duration: const Duration(seconds: 3)));
  }

  void _deploy(AppState st, Host h) async {
    final ok = await st.deployMonitorAgent(h.id.toString());
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? _text(st, '部署成功', 'Deployment succeeded')
              : _text(st, '部署失败', 'Deployment failed')),
          backgroundColor: ok ? AntdTokens.success : AntdTokens.error));
  }

  void _stop(AppState st, Host h) async {
    final ok = await st.stopMonitorAgent(h.id.toString());
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? _text(st, '已停止', 'Stopped')
              : _text(st, '停止失败', 'Failed to stop')),
          backgroundColor: ok ? AntdTokens.success : AntdTokens.error));
  }

  void _showReorderDialog() {
    final st = context.read<AppState>();
    final tempHosts = List<Host>.from(st.hosts);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AntdModal(
              title: Text(_text(st, '主机拖拽排序', 'Reorder hosts')),
              width: 500,
              okText: _text(st, '保存排序', 'Save order'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                final ids = tempHosts.map((h) => h.id).toList();
                final ok = await st.reorderHosts(ids);
                if (ok) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text(_text(st, '主机排序已更新', 'Host order updated')),
                          backgroundColor: AntdTokens.success),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(_text(
                              st, '主机排序保存失败', 'Failed to save host order')),
                          backgroundColor: AntdTokens.error),
                    );
                  }
                }
              },
              child: SizedBox(
                height: 400,
                width: double.maxFinite,
                child: tempHosts.isEmpty
                    ? Center(
                        child: AntdEmpty(
                          description: _text(st, '暂无主机', 'No hosts'),
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: tempHosts.length,
                        onReorder: (oldIndex, newIndex) {
                          setDialogState(() {
                            if (oldIndex < newIndex) {
                              newIndex -= 1;
                            }
                            final item = tempHosts.removeAt(oldIndex);
                            tempHosts.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final h = tempHosts[index];
                          return ListTile(
                            key: ValueKey(h.id),
                            leading: Icon(
                              h.hostType == 'monitor_only'
                                  ? Icons.monitor_heart
                                  : Icons.terminal,
                              color: h.hostType == 'monitor_only'
                                  ? AntdTokens.success
                                  : AntdTokens.primary,
                            ),
                            title: Text(h.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(h.host),
                            trailing: const Icon(Icons.drag_handle),
                          );
                        },
                      ),
              ),
            );
          },
        );
      },
    );
  }

  bool _isOnline(AppState st, Host h) {
    if (h.deletedAt != null) return false;
    if (h.hostType != 'monitor_only' &&
        st.hostConnectionStatus.containsKey(h.id)) {
      return st.hostConnectionStatus[h.id] == true;
    }
    final d = st.monitorData[h.id.toString()];
    return h.status == 'online' || (d != null && d.isNotEmpty);
  }

  String? _latency(AppState st, Host h) {
    final d = st.monitorData[h.id.toString()];
    if (d == null) return null;
    final l = d['latency'];
    if (l != null) return '${l}ms';
    return null;
  }

  int _daysUntil(String? ds) {
    if (ds == null || ds.isEmpty) return 999;
    try {
      return DateTime.parse(ds).difference(DateTime.now()).inDays;
    } catch (_) {
      return 999;
    }
  }

  String _billingLabel(AppState state, String? p) {
    if (p == null || p.isEmpty) return '\u2014';
    return switch (p) {
      'monthly' => Translation.getText(state.locale, 'host.billingMonthly'),
      'quarterly' => Translation.getText(state.locale, 'host.billingQuarterly'),
      'semiannually' =>
        Translation.getText(state.locale, 'host.billingSemiannually'),
      'annually' => Translation.getText(state.locale, 'host.billingAnnually'),
      'biennial' => Translation.getText(state.locale, 'host.billingBiennial'),
      'triennial' => Translation.getText(state.locale, 'host.billingTriennial'),
      '4year' => Translation.getText(state.locale, 'host.billing4Year'),
      '5year' => Translation.getText(state.locale, 'host.billing5Year'),
      '6year' => Translation.getText(state.locale, 'host.billing6Year'),
      '7year' => Translation.getText(state.locale, 'host.billing7Year'),
      '8year' => Translation.getText(state.locale, 'host.billing8Year'),
      '9year' => Translation.getText(state.locale, 'host.billing9Year'),
      '10year' => Translation.getText(state.locale, 'host.billing10Year'),
      _ => p,
    };
  }

  String _remainingValue(Host h) {
    if (h.expirationDate == null ||
        h.billingPeriod == null ||
        h.billingPeriod!.isEmpty ||
        h.billingAmount <= 0) return '\u2014';
    final days = _daysUntil(h.expirationDate);
    if (days <= 0) return '0.00';
    final pd = {
          'monthly': 30,
          'quarterly': 90,
          'semiannually': 180,
          'annually': 365,
          'biennial': 730,
          'triennial': 1095
        }[h.billingPeriod] ??
        30;
    return '${h.currency}${((h.billingAmount / pd) * days).toStringAsFixed(2)}';
  }

  Color _flagColor(String? flag) => switch (flag) {
        'red' => const Color(0xFFFF4D4F),
        'orange' => const Color(0xFFFF7A45),
        'yellow' => const Color(0xFFFAAD14),
        'green' => const Color(0xFF52C41A),
        'blue' => const Color(0xFF1890FF),
        'purple' => const Color(0xFF722ED1),
        _ => Colors.transparent,
      };

  List<Host> _filterHosts(List<Host> hosts, AppState st) {
    final q = _searchText.trim().toLowerCase();
    return hosts.where((h) {
      if (q.isNotEmpty &&
          !h.name.toLowerCase().contains(q) &&
          !h.host.toLowerCase().contains(q)) return false;
      final online = _isOnline(st, h);
      final days = _daysUntil(h.expirationDate);
      return switch (_quickFilter) {
        'online' => online,
        'offline' => !online,
        'monitor' => h.monitorEnabled || h.hostType == 'monitor_only',
        'expiring' => days <= 7 && days > 0,
        'expired' => days <= 0,
        'deleted' => h.deletedAt != null,
        _ => true,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final filtered = _filterHosts(st.hosts, st);

    final columns = <AntdTableColumn<Host>>[
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.name'),
        width: 150,
        cell: (ctx, h, _) => Row(children: [
          if (h.flag != null && h.flag!.isNotEmpty)
            Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    color: _flagColor(h.flag), shape: BoxShape.circle)),
          Icon(
              h.hostType == 'monitor_only'
                  ? Icons.monitor_heart
                  : Icons.terminal,
              size: 14,
              color: h.hostType == 'monitor_only'
                  ? AntdTokens.success
                  : AntdTokens.primary),
          const SizedBox(width: 6),
          Expanded(
              child: Text(h.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      AntdTableColumn(
        title: _text(st, '状态', 'Status'),
        width: 90,
        cell: (ctx, h, _) {
          if (_checkingHostIds.contains(h.id)) {
            return const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            );
          }
          final online = _isOnline(st, h);
          final lat = _latency(st, h);
          if (online && lat != null)
            return AntdTag(preset: AntdTagPreset.success, label: lat);
          if (online)
            return AntdTag(
                preset: AntdTagPreset.success,
                label: _text(st, '在线', 'Online'));
          return AntdTag(
              preset: AntdTagPreset.error, label: _text(st, '离线', 'Offline'));
        },
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.monitor'),
        width: 70,
        cell: (ctx, h, _) => AntdTag(
            preset: h.monitorEnabled
                ? AntdTagPreset.processing
                : AntdTagPreset.defaultStyle,
            label: Translation.getText(
              st.locale,
              h.monitorEnabled
                  ? 'host.monitoringEnabled'
                  : 'host.monitoringDisabled',
            )),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.description'),
        width: 130,
        cell: (ctx, h, _) => Text(
            h.description.isEmpty ? h.host : h.description,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AntdTokens.secondaryTextColor(context))),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.type'),
        width: 80,
        cell: (ctx, h, _) => AntdTag(
            preset: h.hostType == 'monitor_only'
                ? AntdTagPreset.processing
                : AntdTagPreset.success,
            label: Translation.getText(
              st.locale,
              h.hostType == 'monitor_only'
                  ? 'host.monitorOnly'
                  : 'host.controlAndMonitor',
            )),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.expirationDate'),
        width: 100,
        cell: (ctx, h, _) {
          final days = _daysUntil(h.expirationDate);
          return Text(h.expirationDate ?? '\u2014',
              style: TextStyle(
                  fontSize: AntdTokens.fontSizeSM,
                  color: days < 0
                      ? AntdTokens.error
                      : (days <= 7
                          ? AntdTokens.warning
                          : AntdTokens.textColor(context))));
        },
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.billingPeriod'),
        width: 80,
        cell: (ctx, h, _) => Text(_billingLabel(st, h.billingPeriod),
            style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.remainingValueLong'),
        width: 90,
        cell: (ctx, h, _) => Text(_remainingValue(h),
            style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'common.actions'),
        width: 50,
        cell: (ctx, h, _) {
          final isMon = h.hostType == 'monitor_only';
          return AntdActionMenu(
              items: [
                if (h.deletedAt == null && !isMon) ...[
                  AntdActionMenuItem(
                      key: 'test',
                      label: _text(st, '测试连接', 'Test connection'),
                      icon: Icons.wifi_find),
                  AntdActionMenuItem(
                      key: 'deploy',
                      label: _text(st, '部署监控', 'Deploy monitor'),
                      icon: Icons.arrow_circle_down_outlined),
                ],
                if (h.deletedAt == null && h.monitorEnabled) ...[
                  AntdActionMenuItem(
                      key: 'stop',
                      label: _text(st, '停止监控', 'Stop monitor'),
                      icon: Icons.stop_circle_outlined),
                ],
                if (h.deletedAt == null) ...[
                  AntdActionMenuItem(
                      key: 'edit',
                      label: Translation.getText(st.locale, 'common.edit'),
                      icon: Icons.edit),
                  AntdActionMenuItem(
                      key: 'delete',
                      label: Translation.getText(st.locale, 'common.delete'),
                      icon: Icons.delete,
                      danger: true),
                ] else
                  AntdActionMenuItem(
                    key: 'permanent',
                    label:
                        Translation.getText(st.locale, 'host.permanentDelete'),
                    icon: Icons.delete_forever,
                    danger: true,
                  ),
              ],
              onAction: (k) => switch (k) {
                    'test' => _test(st, h),
                    'deploy' => _deploy(st, h),
                    'stop' => _stop(st, h),
                    'edit' => _edit(h),
                    'delete' => _del(st, h),
                    'permanent' => _permanentlyDelete(st, h),
                    _ => null,
                  });
        },
      ),
    ];

    final filterOptions = [
      AntdRadioOption(
          value: 'all',
          label: Translation.getText(st.locale, 'host.filterAll')),
      AntdRadioOption(
          value: 'online',
          label: Translation.getText(st.locale, 'host.filterOnline')),
      AntdRadioOption(
          value: 'offline',
          label: Translation.getText(st.locale, 'host.filterOffline')),
      AntdRadioOption(
          value: 'expiring',
          label: Translation.getText(st.locale, 'host.filterExpiring')),
      AntdRadioOption(
          value: 'expired',
          label: Translation.getText(st.locale, 'host.filterExpired')),
      AntdRadioOption(
          value: 'monitor',
          label: Translation.getText(st.locale, 'host.monitor')),
      if (_showDeleted)
        AntdRadioOption(
          value: 'deleted',
          label: Translation.getText(st.locale, 'host.filterDeleted'),
        ),
    ];

    return Stack(children: [
      Column(children: [
        if (_orphanAgents.isNotEmpty && !_orphanBannerDismissed)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: AntdAlert(
              type: AntdAlertType.warning,
              message: _text(st, '检测到孤立 Agent', 'Orphan agents detected'),
              description: _text(
                st,
                '${_orphanAgents.length} 个已删除或未知主机仍在上报监控数据',
                '${_orphanAgents.length} deleted or unknown hosts are still reporting',
              ),
              closable: true,
              onClose: () => setState(() => _orphanBannerDismissed = true),
              action: AntdButton(
                type: AntdButtonType.link,
                size: AntdSize.small,
                onPressed: () => _showOrphanAgents(st),
                child: Text(_text(st, '查看', 'View')),
              ),
            ),
          ),
        AntdToolbar(height: 48, bordered: true, leading: [
          SizedBox(
              width: 200,
              child: AntdInput(
                  controller: _searchController,
                  placeholder:
                      Translation.getText(st.locale, 'host.searchPlaceholder'),
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _searchText = v))),
        ], trailing: [
          AntdButton(
            size: AntdSize.small,
            onPressed: _selectedHostIds.isEmpty || _batchLoading
                ? null
                : () => _runBatch(
                      st,
                      st.deployMonitorAgents,
                      st.locale == 'zh' ? '批量部署' : 'Batch deploy',
                    ),
            icon: Icons.arrow_circle_down_outlined,
            loading: _batchLoading,
            child: Text(
                '${st.locale == 'zh' ? '批量部署' : 'Deploy'} (${_selectedHostIds.length})'),
          ),
          AntdButton(
            size: AntdSize.small,
            onPressed: _selectedHostIds.isEmpty || _batchLoading
                ? null
                : () => _runBatch(
                      st,
                      st.stopMonitorAgents,
                      st.locale == 'zh' ? '批量停止' : 'Batch stop',
                    ),
            icon: Icons.stop_circle_outlined,
            child: Text(st.locale == 'zh' ? '批量停止' : 'Stop'),
          ),
          if (_selectedHostIds.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: _text(st, '批量通知设置', 'Batch notifications'),
              onSelected: (value) {
                switch (value) {
                  case 'traffic_on':
                    _runBatchSetting(st, 'notify_traffic_enabled', true);
                  case 'traffic_off':
                    _runBatchSetting(st, 'notify_traffic_enabled', false);
                  case 'offline_on':
                    _runBatchSetting(st, 'notify_offline_enabled', true);
                  case 'offline_off':
                    _runBatchSetting(st, 'notify_offline_enabled', false);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'traffic_on',
                  child: Text(_text(st, '启用流量警告', 'Enable traffic alerts')),
                ),
                PopupMenuItem(
                  value: 'traffic_off',
                  child: Text(_text(st, '停用流量警告', 'Disable traffic alerts')),
                ),
                PopupMenuItem(
                  value: 'offline_on',
                  child: Text(_text(st, '启用上下线通知', 'Enable offline alerts')),
                ),
                PopupMenuItem(
                  value: 'offline_off',
                  child: Text(_text(st, '停用上下线通知', 'Disable offline alerts')),
                ),
              ],
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.notifications_outlined, size: 18),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Translation.getText(st.locale, 'host.showDeleted'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 6),
              AntdSwitch(
                size: AntdSwitchSize.small,
                value: _showDeleted,
                onChanged: (value) {
                  setState(() {
                    _showDeleted = value;
                    if (!value && _quickFilter == 'deleted') {
                      _quickFilter = 'all';
                    }
                  });
                  _loadHosts();
                },
              ),
            ],
          ),
          AntdButton(icon: Icons.refresh, onPressed: _loadHosts),
          AntdButton(icon: Icons.swap_vert, onPressed: _showReorderDialog),
          AntdButton(
              type: AntdButtonType.primary,
              icon: Icons.add,
              onPressed: _add,
              child: Text(Translation.getText(st.locale, 'host.addHost'))),
        ]),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: AntdTokens.cardBodyPadding(context), vertical: 6),
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                AntdRadioGroup<String>(
                    size: AntdRadioSize.small,
                    value: _quickFilter,
                    options: filterOptions,
                    onChanged: (v) => setState(() => _quickFilter = v)),
              ])),
        ),
        Expanded(
            child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AntdTokens.contentPadding(context)),
                child: Container(
                    decoration: BoxDecoration(
                        color: AntdTokens.containerColor(context),
                        borderRadius:
                            BorderRadius.circular(AntdTokens.cardRadius),
                        border: Border.all(
                            color: AntdTokens.borderSecondaryColor(context))),
                    clipBehavior: Clip.antiAlias,
                    child: AntdTable<Host>(
                        rowKey: (h) => h.id.toString(),
                        loading: _isLoading,
                        data: filtered,
                        columns: columns,
                        selectedKeys: _selectedHostIds,
                        onSelectionChanged: (keys) => setState(() {
                              _selectedHostIds
                                ..clear()
                                ..addAll(keys);
                            }),
                        emptyWidget: const AntdEmpty(
                            description: '\u6682\u65e0\u4e3b\u673a'),
                        onRowTap: (h) {
                          if (h.deletedAt == null) _edit(h);
                        })))),
      ]),
    ]);
  }
}
