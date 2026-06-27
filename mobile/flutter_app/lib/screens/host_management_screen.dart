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
  final _searchController = TextEditingController();

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  Future<void> _loadHosts() async {
    setState(() => _isLoading = true);
    await context.read<AppState>().fetchHosts();
    if (mounted) setState(() => _isLoading = false);
  }

  void _add() { showDialog(context: context, builder: (_) => const HostEditDialog()).then((_) => _loadHosts()); }

  void _edit(Host h) {
    showDialog(context: context, builder: (_) => HostEditDialog(host: {
      'id': h.id, 'name': h.name, 'host': h.host, 'port': h.port, 'username': h.username,
      'host_type': h.hostType, 'monitor_enabled': h.monitorEnabled,
      'net_traffic_limit': h.netTrafficLimit, 'net_reset_day': h.netResetDay,
      'net_traffic_counter_mode': h.netTrafficCounterMode,
      'net_traffic_used_adjustment': h.netTrafficUsedAdjustment,
      'expiration_date': h.expirationDate, 'billing_amount': h.billingAmount,
      'billing_period': h.billingPeriod, 'currency': h.currency, 'sort_order': h.sortOrder,
      'flag': h.flag,
    })).then((_) => _loadHosts());
  }

  void _del(AppState st, Host h) {
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(Translation.getText(st.locale, 'common.confirmDelete')), width: 400, danger: true,
      okText: Translation.getText(st.locale, 'common.confirm'), cancelText: Translation.getText(st.locale, 'common.cancel'),
      onOk: () async { await st.deleteHost(h.id.toString()); _loadHosts(); },
      child: Text('\u786e\u5b9a\u8981\u5220\u9664 ${h.name} \u5417\uff1f'),
    ));
  }

  void _test(AppState st, Host h) async {
    final r = await st.testHostConnection(h.id.toString());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['message']??''), backgroundColor: r['success']==true?AntdTokens.success:AntdTokens.error, duration: const Duration(seconds:3)));
  }
  void _deploy(AppState st, Host h) async {
    final ok = await st.deployMonitorAgent(h.id.toString());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok?'\u90e8\u7f72\u6210\u529f':'\u90e8\u7f72\u5931\u8d25'), backgroundColor: ok?AntdTokens.success:AntdTokens.error));
  }
  void _stop(AppState st, Host h) async {
    final ok = await st.stopMonitorAgent(h.id.toString());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok?'\u5df2\u505c\u6b62':'\u505c\u6b62\u5931\u8d25'), backgroundColor: ok?AntdTokens.success:AntdTokens.error));
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
              title: const Text('主机拖拽排序'),
              width: 500,
              okText: '保存排序',
              cancelText: '取消',
              onOk: () async {
                final ids = tempHosts.map((h) => h.id).toList();
                final ok = await st.reorderHosts(ids);
                if (ok) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('主机排序已更新'), backgroundColor: AntdTokens.success),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('主机排序保存失败'), backgroundColor: AntdTokens.error),
                    );
                  }
                }
              },
              child: SizedBox(
                height: 400,
                width: double.maxFinite,
                child: tempHosts.isEmpty
                    ? const Center(child: AntdEmpty(description: '暂无主机'))
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
                              h.hostType == 'monitor_only' ? Icons.monitor_heart : Icons.terminal,
                              color: h.hostType == 'monitor_only' ? AntdTokens.success : AntdTokens.primary,
                            ),
                            title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final d = st.monitorData[h.id.toString()];
    return d != null && d.isNotEmpty;
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
    try { return DateTime.parse(ds).difference(DateTime.now()).inDays; } catch (_) { return 999; }
  }

  String _billingLabel(String? p) {
    if (p == null || p.isEmpty) return '\u2014';
    return switch (p) {
      'monthly' => '\u6708\u4ed8', 'quarterly' => '\u5b63\u4ed8', 'semiannually' => '\u534a\u5e74\u4ed8', 'annually' => '\u5e74\u4ed8',
      'biennial' => '2\u5e74\u4ed8', 'triennial' => '3\u5e74\u4ed8', '4year' => '4\u5e74\u4ed8', '5year' => '5\u5e74\u4ed8',
      '6year' => '6\u5e74\u4ed8', '7year' => '7\u5e74\u4ed8', '8year' => '8\u5e74\u4ed8', '9year' => '9\u5e74\u4ed8', '10year' => '10\u5e74\u4ed8',
      _ => p,
    };
  }

  String _remainingValue(Host h) {
    if (h.expirationDate == null || h.billingPeriod == null || h.billingPeriod!.isEmpty || h.billingAmount <= 0) return '\u2014';
    final days = _daysUntil(h.expirationDate);
    if (days <= 0) return '0.00';
    final pd = {'monthly':30,'quarterly':90,'semiannually':180,'annually':365,'biennial':730,'triennial':1095}[h.billingPeriod]??30;
    return '${h.currency}${((h.billingAmount/pd)*days).toStringAsFixed(2)}';
  }

  Color _flagColor(String? flag) => switch (flag) {
    'red' => const Color(0xFFFF4D4F), 'orange' => const Color(0xFFFF7A45), 'yellow' => const Color(0xFFFAAD14),
    'green' => const Color(0xFF52C41A), 'blue' => const Color(0xFF1890FF), 'purple' => const Color(0xFF722ED1),
    _ => Colors.transparent,
  };

  List<Host> _filterHosts(List<Host> hosts, AppState st) {
    final q = _searchText.trim().toLowerCase();
    return hosts.where((h) {
      if (q.isNotEmpty && !h.name.toLowerCase().contains(q) && !h.host.toLowerCase().contains(q)) return false;
      final online = _isOnline(st, h);
      final days = _daysUntil(h.expirationDate);
      return switch (_quickFilter) {
        'online' => online, 'offline' => !online, 'monitor' => h.monitorEnabled || h.hostType == 'monitor_only',
        'expiring' => days <= 7 && days > 0,
        'expired' => days <= 0,
        'deleted' => _showDeleted,
        _ => true,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final filtered = _filterHosts(st.hosts, st);

    final columns = <AntdTableColumn<Host>>[
      AntdTableColumn(title: '\u540d\u79f0', width: 150,
        cell: (ctx, h, _) => Row(children: [
          if (h.flag != null && h.flag!.isNotEmpty)
            Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: _flagColor(h.flag), shape: BoxShape.circle)),
          Icon(h.hostType=='monitor_only'?Icons.monitor_heart:Icons.terminal, size: 14,
              color: h.hostType=='monitor_only'?AntdTokens.success:AntdTokens.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(h.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      AntdTableColumn(title: '\u72b6\u6001', width: 90,
        cell: (ctx, h, _) {
          final online = _isOnline(st, h);
          final lat = _latency(st, h);
          if (online && lat != null) return AntdTag(preset: AntdTagPreset.success, label: lat);
          if (online) return AntdTag(preset: AntdTagPreset.success, label: '\u5728\u7ebf');
          return AntdTag(preset: AntdTagPreset.error, label: '\u79bb\u7ebf');
        },
      ),
      AntdTableColumn(title: '\u76d1\u63a7', width: 70,
        cell: (ctx, h, _) => AntdTag(
          preset: h.monitorEnabled ? AntdTagPreset.processing : AntdTagPreset.defaultStyle,
          label: h.monitorEnabled ? '\u5df2\u5f00\u542f' : '\u672a\u5f00\u542f'),
      ),
      AntdTableColumn(title: '\u63cf\u8ff0', width: 130,
        cell: (ctx, h, _) => Text(h.host, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AntdTokens.secondaryTextColor(context))),
      ),
      AntdTableColumn(title: '\u7c7b\u578b', width: 80,
        cell: (ctx, h, _) => AntdTag(
          preset: h.hostType=='monitor_only'?AntdTagPreset.processing:AntdTagPreset.success,
          label: h.hostType=='monitor_only'?'\u4ec5\u76d1\u63a7':'\u63a7\u5236+\u76d1\u63a7'),
      ),
      AntdTableColumn(title: '\u5230\u671f', width: 100,
        cell: (ctx, h, _) {
          final days = _daysUntil(h.expirationDate);
          return Text(h.expirationDate??'\u2014',
            style: TextStyle(fontSize: AntdTokens.fontSizeSM,
                color: days<0?AntdTokens.error:(days<=7?AntdTokens.warning:AntdTokens.textColor(context))));
        },
      ),
      AntdTableColumn(title: '\u8ba1\u8d39\u5468\u671f', width: 80,
        cell: (ctx, h, _) => Text(_billingLabel(h.billingPeriod), style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(title: '\u5269\u4f59\u4ef7\u503c', width: 90,
        cell: (ctx, h, _) => Text(_remainingValue(h), style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(title: '\u64cd\u4f5c', width: 50,
        cell: (ctx, h, _) {
          final isMon = h.hostType == 'monitor_only';
          return AntdActionMenu(items: [
            if (!isMon) const AntdActionMenuItem(key: 'test', label: '\u6d4b\u8bd5\u8fde\u63a5', icon: Icons.wifi_find),
            if (h.monitorEnabled) ...[
              const AntdActionMenuItem(key: 'deploy', label: '\u90e8\u7f72\u76d1\u63a7', icon: Icons.arrow_circle_down_outlined),
              const AntdActionMenuItem(key: 'stop', label: '\u505c\u6b62\u76d1\u63a7', icon: Icons.stop_circle_outlined),
            ],
            const AntdActionMenuItem(key: 'edit', label: '\u7f16\u8f91', icon: Icons.edit),
            const AntdActionMenuItem(key: 'delete', label: '\u5220\u9664', icon: Icons.delete, danger: true),
          ], onAction: (k) => switch (k) {
            'test' => _test(st, h), 'deploy' => _deploy(st, h), 'stop' => _stop(st, h),
            'edit' => _edit(h), 'delete' => _del(st, h), _ => null,
          });
        },
      ),
    ];

    final filterOptions = [
      const AntdRadioOption(value: 'all', label: '\u5168\u90e8'),
      const AntdRadioOption(value: 'online', label: '\u5728\u7ebf'),
      const AntdRadioOption(value: 'offline', label: '\u79bb\u7ebf'),
      const AntdRadioOption(value: 'expiring', label: '\u5373\u5c06\u5230\u671f'),
      const AntdRadioOption(value: 'expired', label: '\u5df2\u5230\u671f'),
      const AntdRadioOption(value: 'monitor', label: '\u76d1\u63a7'),
    ];

    return Stack(children: [
      Column(children: [
        AntdToolbar(height: 48, bordered: true, leading: [
          SizedBox(width: 200, child: AntdInput(controller: _searchController, placeholder: '\u641c\u7d22\u4e3b\u673a',
            prefixIcon: Icons.search, onChanged: (v) => setState(() => _searchText = v))),
        ], trailing: [
          AntdButton(icon: Icons.refresh, onPressed: _loadHosts),
          AntdButton(icon: Icons.swap_vert, onPressed: _showReorderDialog),
          AntdButton(type: AntdButtonType.primary, icon: Icons.add, onPressed: _add, child: const Text('\u6dfb\u52a0\u4e3b\u673a')),
        ]),
        Padding(padding: EdgeInsets.symmetric(horizontal: AntdTokens.cardBodyPadding(context), vertical: 6),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            AntdRadioGroup<String>(size: AntdRadioSize.small, value: _quickFilter, options: filterOptions,
                onChanged: (v) => setState(() => _quickFilter = v)),
          ])),
        ),
        Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: AntdTokens.contentPadding(context)),
          child: Container(decoration: BoxDecoration(color: AntdTokens.containerColor(context),
            borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
            border: Border.all(color: AntdTokens.borderSecondaryColor(context))),
            clipBehavior: Clip.antiAlias,
            child: AntdTable<Host>(rowKey: (h) => h.id.toString(), loading: _isLoading,
              data: filtered, columns: columns,
              emptyWidget: const AntdEmpty(description: '\u6682\u65e0\u4e3b\u673a'),
              onRowTap: (h) => _edit(h))))),
      ]),
      Positioned(bottom: 16, right: 16, child: FloatingActionButton(
        onPressed: _add, backgroundColor: AntdTokens.primary, mini: true,
        child: const Icon(Icons.add, color: Colors.white))),
    ]);
  }
}
