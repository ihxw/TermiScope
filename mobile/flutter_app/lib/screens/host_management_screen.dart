import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../utils/translation.dart';
import '../utils/host_monitor_commands.dart';
import '../widgets/antd/index.dart';
import 'host_edit_dialog.dart';

class HostManagementScreen extends StatefulWidget {
  const HostManagementScreen({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<HostManagementScreen> createState() => _HostManagementScreenState();
}

class _HostManagementScreenState extends State<HostManagementScreen> {
  bool _isLoading = false;
  bool _loadError = false;
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
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHosts());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHosts() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final loaded = await state.fetchHosts(includeDeleted: _showDeleted);
    await _loadOrphanAgents(state);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadError = !loaded;
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
        builder: (dialogContext) => AntdModal(
              title:
                  Text(Translation.getText(st.locale, 'common.confirmDelete')),
              width: 400,
              danger: true,
              okText: Translation.getText(st.locale, 'common.confirm'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                await st.deleteHost(h.id.toString());
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                await _loadHosts();
              },
              child: Text(
                '${Translation.getText(st.locale, 'host.deleteConfirm')}\n${h.name}',
              ),
            ));
  }

  void _permanentlyDelete(AppState st, Host h) {
    showDialog(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(Translation.getText(st.locale, 'host.permanentDelete')),
        width: 420,
        danger: true,
        okText: Translation.getText(st.locale, 'host.permanentDelete'),
        cancelText: Translation.getText(st.locale, 'common.cancel'),
        onOk: () async {
          final ok = await st.permanentlyDeleteHost(h.id.toString());
          if (!mounted) return;
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
    ).toList();
    if (mounted) {
      setState(() => _checkingHostIds.addAll(targets.map((host) => host.id)));
    }
    await Future.wait(targets.map((host) async {
      try {
        if (state.isLocalNetworkHost(host.id)) {
          await state.testLocalHostConnection(host);
        } else {
          await state.testHostConnection(host.id.toString());
        }
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
    final ids = _selectedHostIds
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => state.hosts.any(
              (host) => host.id == id && host.deletedAt == null,
            ))
        .toList();
    if (ids.isEmpty) return;
    setState(() => _batchLoading = true);
    final result = await state.updateHostsSetting(ids, {field: value});
    if (!mounted) return;
    setState(() {
      _batchLoading = false;
      _selectedHostIds.clear();
    });
    _showResult(
      result['failed'] == 0,
      '${value ? 'Enable' : 'Disable'}: ${result['success']} / ${ids.length}',
    );
    await _loadHosts();
  }

  void _confirmBatchAction(AppState state, {required bool deploy}) {
    final eligible = state.hosts
        .where((host) =>
            _selectedHostIds.contains(host.id.toString()) &&
            host.deletedAt == null &&
            host.hostType != 'monitor_only')
        .toList();
    if (eligible.isEmpty) {
      _showResult(
        false,
        _text(state, '所选主机无法执行此操作',
            'No selected hosts support this action'),
      );
      return;
    }
    final skipped = _selectedHostIds.length - eligible.length;
    var insecure = false;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AntdModal(
          title: Text(_text(
            state,
            deploy ? '批量部署监控' : '批量停止监控',
            deploy ? 'Batch deploy monitoring' : 'Batch stop monitoring',
          )),
          width: 460,
          danger: !deploy,
          okText: _text(state, deploy ? '部署' : '停止', deploy ? 'Deploy' : 'Stop'),
          cancelText: Translation.getText(state.locale, 'common.cancel'),
          onOk: () {
            Navigator.of(dialogContext).pop();
            _runBatch(
              state,
              deploy
                  ? (ids) => state.deployMonitorAgents(
                        ids,
                        insecure: insecure,
                      )
                  : state.stopMonitorAgents,
              _text(
                state,
                deploy ? '批量部署' : '批量停止',
                deploy ? 'Batch deploy' : 'Batch stop',
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_text(
                state,
                '将对 ${eligible.length} 台主机执行操作。',
                'This action will run on ${eligible.length} hosts.',
              )),
              if (skipped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  _text(
                    state,
                    '已跳过 $skipped 台仅监控或已删除主机。',
                    'Skipped $skipped monitor-only or deleted hosts.',
                  ),
                  style: const TextStyle(color: AntdTokens.warning),
                ),
              ],
              if (deploy) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: insecure,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_text(
                    state,
                    '跳过 SSL/主机指纹验证（不安全）',
                    'Skip SSL/host fingerprint verification (unsafe)',
                  )),
                  onChanged: (value) =>
                      setDialogState(() => insecure = value == true),
                ),
              ],
            ],
          ),
        ),
      ),
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

  void _deploy(AppState st, Host h) {
    var insecure = false;
    var loading = false;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AntdModal(
          title: Text(_text(st, '部署监控 Agent', 'Deploy monitor agent')),
          width: 440,
          confirmLoading: loading,
          okText: _text(st, '部署', 'Deploy'),
          cancelText: Translation.getText(st.locale, 'common.cancel'),
          onOk: loading
              ? null
              : () async {
                  setDialogState(() => loading = true);
                  final ok = await st.deployMonitorAgent(
                    h.id.toString(),
                    insecure: insecure,
                  );
                  if (!mounted) return;
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  _showResult(
                    ok,
                    ok
                        ? _text(st, '部署成功', 'Deployment succeeded')
                        : _text(st, '部署失败', 'Deployment failed'),
                  );
                  await _loadHosts();
                },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_text(
                st,
                '确定要向 ${h.name} 部署监控 Agent 吗？',
                'Deploy the monitor agent to ${h.name}?',
              )),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: insecure,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(_text(
                  st,
                  '跳过 SSL/主机指纹验证（不安全）',
                  'Skip SSL/host fingerprint verification (unsafe)',
                )),
                onChanged: (value) =>
                    setDialogState(() => insecure = value == true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stop(AppState st, Host h) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: Text(_text(st, '停止监控', 'Stop monitor')),
        width: 400,
        danger: true,
        okText: _text(st, '停止', 'Stop'),
        cancelText: Translation.getText(st.locale, 'common.cancel'),
        onOk: () async {
          final ok = await st.stopMonitorAgent(h.id.toString());
          if (!mounted) return;
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          _showResult(
            ok,
            ok
                ? _text(st, '已停止', 'Stopped')
                : _text(st, '停止失败', 'Failed to stop'),
          );
          await _loadHosts();
        },
        child: Text(_text(
          st,
          '确定要停止 ${h.name} 的监控 Agent 吗？',
          'Stop the monitor agent on ${h.name}?',
        )),
      ),
    );
  }

  void _showReorderDialog() {
    final st = context.read<AppState>();
    final tempHosts = st.hosts
        .where((host) => host.deletedAt == null)
        .toList(growable: true);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AntdModal(
              title: Text(_text(st, '主机拖拽排序', 'Reorder hosts')),
              width: 500,
              okText: _text(st, '保存排序', 'Save order'),
              cancelText: Translation.getText(st.locale, 'common.cancel'),
              onOk: () async {
                final ids = tempHosts.map((h) => h.id).toList();
                final ok = await st.reorderHosts(ids);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
                await _loadHosts();
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
    if (d is Map) {
      final status = d['status']?.toString().toLowerCase();
      if (status != null) {
        return d['_offline'] != true && status == 'online';
      }
    }
    return h.status == 'online';
  }

  String? _latency(AppState st, Host h) {
    final checked = st.hostConnectionLatency[h.id];
    if (checked != null) return '${checked}ms';
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

  String _remainingValue(AppState state, Host h) {
    if (h.expirationDate == null ||
        h.billingPeriod == null ||
        h.billingPeriod!.isEmpty ||
        h.billingAmount <= 0) return '\u2014';
    final days = _daysUntil(h.expirationDate);
    if (days < 0) return _text(state, '已过期', 'Expired');
    final pd = {
          'monthly': 30,
          'quarterly': 90,
          'semiannually': 180,
          'annually': 365,
          'biennial': 730,
          'triennial': 1095,
          '4year': 1460,
          '5year': 1825,
          '6year': 2190,
          '7year': 2555,
          '8year': 2920,
          '9year': 3285,
          '10year': 3650,
        }[h.billingPeriod] ??
        30;
    final symbol = switch (h.currency) {
      'USD' => r'$',
      'EUR' => '\u20AC',
      'GBP' => '\u00A3',
      _ => '\u00A5',
    };
    return '$symbol${((h.billingAmount / pd) * days).toStringAsFixed(2)} '
        '($days${_text(state, '天', 'd')})';
  }

  Color _flagColor(String? flag) => switch (flag) {
        'red' => const Color(0xFFFF4D4F),
        'orange' => const Color(0xFFFF7A45),
        'yellow' => const Color(0xFFFAAD14),
        'green' => const Color(0xFF52C41A),
        'blue' => const Color(0xFF1890FF),
        'purple' => const Color(0xFF722ED1),
        'gray' => const Color(0xFF8E8E93),
        _ => Colors.transparent,
      };

  String _osLabel(String? os) {
    os = (os ?? '').toLowerCase();
    if (os.contains('win')) return 'Windows';
    if (os.contains('darwin') || os.contains('mac')) return 'macOS';
    return 'Linux';
  }

  IconData _osIcon(String? os) {
    os = (os ?? '').toLowerCase();
    if (os.contains('win')) return Icons.window_outlined;
    if (os.contains('darwin') || os.contains('mac')) {
      return Icons.desktop_mac_outlined;
    }
    return Icons.dns_outlined;
  }

  Future<void> _showMonitorCommand(
    AppState state,
    Host host, {
    bool uninstall = false,
  }) async {
    Map<String, dynamic> details;
    try {
      details = await state.fetchHostDetails(host.id.toString());
    } catch (_) {
      _showResult(
        false,
        _text(state, '无法读取主机监控密钥', 'Unable to load monitor secret'),
      );
      return;
    }
    if (!mounted) return;

    final secret = details['monitor_secret']?.toString() ?? '';
    if (secret.isEmpty) {
      _showResult(
        false,
        _text(state, '主机尚未生成监控密钥', 'Monitor secret is unavailable'),
      );
      return;
    }

    var platform = switch (host.osType.toLowerCase()) {
      final os when os.contains('win') => 'windows',
      final os when os.contains('darwin') || os.contains('mac') => 'darwin',
      _ => 'linux',
    };

    String command() => uninstall
        ? HostMonitorCommands.uninstall(
            baseUrl: state.apiService.baseUrl ?? '',
            hostId: host.id,
            secret: secret,
          )
        : HostMonitorCommands.install(
            baseUrl: state.apiService.baseUrl ?? '',
            hostId: host.id,
            secret: secret,
            platform: platform,
          );

    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AntdModal(
          title: Text(_text(
            state,
            uninstall ? '手动卸载监控 Agent' : '手动安装监控 Agent',
            uninstall ? 'Manual uninstall agent' : 'Manual install agent',
          )),
          width: 650,
          showFooter: false,
          child: SizedBox(
            height: uninstall ? 230 : 330,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AntdAlert(
                  type: uninstall ? AntdAlertType.warning : AntdAlertType.info,
                  message: _text(
                    state,
                    uninstall
                        ? '请在目标主机上以 root 权限执行以下命令'
                        : '请在目标主机上执行以下安装命令',
                    uninstall
                        ? 'Run this command as root on the target host'
                        : 'Run this install command on the target host',
                  ),
                  showIcon: true,
                ),
                if (!uninstall) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: AntdRadioGroup<String>(
                      size: AntdRadioSize.small,
                      value: platform,
                      options: const [
                        AntdRadioOption(value: 'linux', label: 'Linux'),
                        AntdRadioOption(value: 'darwin', label: 'macOS'),
                        AntdRadioOption(value: 'windows', label: 'Windows'),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => platform = value),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        host.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    AntdButton(
                      size: AntdSize.small,
                      type: AntdButtonType.primary,
                      icon: Icons.copy,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: command()));
                        if (!mounted) return;
                        _showResult(
                          true,
                          _text(state, '命令已复制', 'Command copied'),
                        );
                      },
                      child: Text(_text(state, '复制', 'Copy')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AntdTokens.containerSecondaryColor(dialogContext),
                      border: Border.all(
                        color: AntdTokens.borderSecondaryColor(dialogContext),
                      ),
                      borderRadius: BorderRadius.circular(AntdTokens.radius),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        command(),
                        style: const TextStyle(
                          fontFamily: 'TermiScope Mono',
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Host> _filterHosts(List<Host> hosts, AppState st) {
    final q = _searchText.trim().toLowerCase();
    return hosts.where((h) {
      if (!_showDeleted && h.deletedAt != null) return false;
      if (q.isNotEmpty &&
          !h.name.toLowerCase().contains(q) &&
          !h.host.toLowerCase().contains(q) &&
          !h.username.toLowerCase().contains(q) &&
          !h.groupName.toLowerCase().contains(q) &&
          !h.description.toLowerCase().contains(q) &&
          !h.tags.toLowerCase().contains(q)) return false;
      final online = _isOnline(st, h);
      final days = _daysUntil(h.expirationDate);
      return switch (_quickFilter) {
        'online' => online,
        'offline' => !online,
        'monitor' => h.monitorEnabled || h.hostType == 'monitor_only',
        'expiring' => days <= 7 && days > 0,
        'expired' => days < 0,
        'deleted' => h.deletedAt != null,
        _ => true,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final filtered = _filterHosts(st.hosts, st);
    final isMobile =
        MediaQuery.sizeOf(context).width <= AntdTokens.mobileBreakpoint;
    final canReorder = _searchText.trim().isEmpty &&
        !_showDeleted &&
        _quickFilter == 'all' &&
        !_isLoading;

    final columns = <AntdTableColumn<Host>>[
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.name'),
        width: 180,
        cell: (ctx, h, _) => Row(children: [
          if (h.flag != null && h.flag!.isNotEmpty)
            Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                    color: _flagColor(h.flag), shape: BoxShape.circle)),
          Tooltip(
            message: _osLabel(h.osType),
            child: Icon(_osIcon(h.osType),
                size: 16, color: AntdTokens.textColor(context)),
          ),
          const SizedBox(width: 6),
          Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.name, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(h.host, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AntdTokens.secondaryTextColor(context))),
                ],
              )),
        ]),
      ),
      AntdTableColumn(
        title: _text(st, '状态', 'Status'),
        width: 90,
        cell: (ctx, h, _) {
          if (h.deletedAt != null) {
            return AntdTag(
              preset: AntdTagPreset.defaultStyle,
              label: _text(st, '已删除', 'Deleted'),
            );
          }
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
      if (!isMobile) AntdTableColumn(
        title: _text(st, '本地网络', 'Local network'),
        width: 92,
        cell: (ctx, h, _) => Tooltip(
          message: kIsWeb
              ? _text(st, 'Web 端不支持本机网络直连',
                  'Direct local access is unavailable on Web')
              : _text(
                  st,
                  '由 Flutter 应用所在设备直接连接此主机',
                  'Connect directly from this Flutter device',
                ),
          child: AntdSwitch(
            size: AntdSwitchSize.small,
            value: st.isLocalNetworkHost(h.id),
            onChanged:
                kIsWeb || h.deletedAt != null || h.hostType == 'monitor_only'
                    ? null
                    : (enabled) async {
                        await st.setLocalNetworkHost(h.id, enabled);
                        if (!mounted) return;
                        setState(() => _checkingHostIds.add(h.id));
                        try {
                          if (enabled) {
                            await st.testLocalHostConnection(h);
                          } else {
                            await st.testHostConnection(h.id.toString());
                          }
                        } finally {
                          if (mounted) {
                            setState(() => _checkingHostIds.remove(h.id));
                          }
                        }
                      },
          ),
        ),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'host.monitor'),
        width: 80,
        cell: (ctx, h, _) => AntdTag(
            preset: h.monitorEnabled
                ? AntdTagPreset.processing
                : AntdTagPreset.defaultStyle,
            label: Translation.getText(
              st.locale,
              h.monitorEnabled
                  ? 'monitor.enabled'
                  : 'monitor.disabled',
            )),
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
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.port'),
        width: 60,
        cell: (ctx, h, _) => Text('${h.port}'),
      ),
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.username'),
        width: 100,
        cell: (ctx, h, _) => Text(
          h.username,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.group'),
        width: 100,
        cell: (ctx, h, _) => Text(
          h.groupName.isEmpty ? '\u2014' : h.groupName,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.description'),
        width: 130,
        cell: (ctx, h, _) => Text(
            h.description.isEmpty ? '\u2014' : h.description,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AntdTokens.secondaryTextColor(context))),
      ),
      if (!isMobile) AntdTableColumn(
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
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.billingPeriod'),
        width: 80,
        cell: (ctx, h, _) => Text(_billingLabel(st, h.billingPeriod),
            style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      if (!isMobile) AntdTableColumn(
        title: Translation.getText(st.locale, 'host.remainingValueLong'),
        width: 120,
        cell: (ctx, h, _) => Text(_remainingValue(st, h),
            style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(
        title: Translation.getText(st.locale, 'common.actions'),
        width: isMobile ? 52 : 200,
        cell: (ctx, h, _) {
          final isMon = h.hostType == 'monitor_only';
          if (isMobile) {
            return AntdDropdown<String>(
              items: [
                AntdDropdownItem(
                  value: 'deploy',
                  label: _text(st, '自动部署', 'Auto deploy'),
                  icon: Icons.cloud_upload_outlined,
                  disabled: isMon || h.deletedAt != null,
                ),
                AntdDropdownItem(
                  value: 'manual',
                  label: _text(st, '手动安装', 'Manual install'),
                  icon: Icons.content_copy,
                  disabled: h.deletedAt != null,
                ),
                AntdDropdownItem(
                  value: 'stop',
                  label: _text(st, '停止监控', 'Stop monitor'),
                  icon: Icons.stop_circle_outlined,
                  danger: true,
                  disabled: isMon || h.deletedAt != null,
                ),
                AntdDropdownItem(
                  value: 'uninstall',
                  label: _text(st, '手动卸载', 'Manual uninstall'),
                  icon: Icons.delete_sweep_outlined,
                  danger: true,
                  disabled: h.deletedAt != null,
                ),
                const AntdDropdownItem(
                  value: 'divider',
                  label: '',
                  divider: true,
                  disabled: true,
                ),
                AntdDropdownItem(
                  value: 'connect',
                  label: _text(st, '连接', 'Connect'),
                  icon: Icons.link,
                  disabled: isMon || h.deletedAt != null,
                ),
                AntdDropdownItem(
                  value: 'edit',
                  label: _text(st, '编辑', 'Edit'),
                  icon: Icons.edit,
                  disabled: h.deletedAt != null,
                ),
                AntdDropdownItem(
                  value: h.deletedAt == null ? 'delete' : 'permanent',
                  label: h.deletedAt == null
                      ? _text(st, '删除', 'Delete')
                      : _text(st, '彻底删除', 'Permanently delete'),
                  icon: h.deletedAt == null
                      ? Icons.delete_outline
                      : Icons.delete_forever,
                  danger: true,
                ),
              ],
              onSelected: (key) {
                switch (key) {
                  case 'deploy': _deploy(st, h);
                  case 'manual': _showMonitorCommand(st, h);
                  case 'stop': _stop(st, h);
                  case 'uninstall':
                    _showMonitorCommand(st, h, uninstall: true);
                  case 'connect': st.addTerminal(h);
                  case 'edit': _edit(h);
                  case 'delete': _del(st, h);
                  case 'permanent': _permanentlyDelete(st, h);
                }
              },
              child: AntdButton(
                size: AntdSize.small,
                icon: Icons.more_horiz,
                onPressed: () {},
              ),
            );
          }
          if (h.deletedAt != null) {
            return AntdButton(
              size: AntdSize.small,
              icon: Icons.delete_forever,
              danger: true,
              onPressed: () => _permanentlyDelete(st, h),
              child: Text(_text(st, '彻底删除', 'Permanently delete')),
            );
          }
          return Row(mainAxisSize: MainAxisSize.min, children: [
            AntdDropdown<String>(items: [
              AntdDropdownItem(value: 'deploy', label: _text(st, '自动部署', 'Auto deploy'), icon: Icons.cloud_upload_outlined, disabled: isMon),
              AntdDropdownItem(value: 'manual', label: _text(st, '手动安装', 'Manual install'), icon: Icons.content_copy),
              AntdDropdownItem(value: 'stop', label: _text(st, '停止监控', 'Stop monitor'), icon: Icons.stop_circle_outlined, danger: true, disabled: isMon),
              AntdDropdownItem(value: 'uninstall', label: _text(st, '手动卸载', 'Manual uninstall'), icon: Icons.delete_sweep_outlined, danger: true),
            ], onSelected: (key) {
              switch (key) {
                case 'deploy': _deploy(st, h);
                case 'manual': _showMonitorCommand(st, h);
                case 'stop': _stop(st, h);
                case 'uninstall': _showMonitorCommand(st, h, uninstall: true);
              }
            }, child: AntdButton(size: AntdSize.small, icon: Icons.dashboard_outlined, onPressed: () {}, child: Text(_text(st, '监控', 'Monitor')))),
            const SizedBox(width: 4),
            AntdButton(size: AntdSize.small, icon: Icons.link, onPressed: isMon ? null : () => st.addTerminal(h)),
            const SizedBox(width: 4),
            AntdButton(size: AntdSize.small, icon: Icons.edit, onPressed: h.deletedAt != null ? null : () => _edit(h)),
            const SizedBox(width: 4),
            AntdButton(size: AntdSize.small, icon: h.deletedAt == null ? Icons.delete : Icons.delete_forever, danger: true, onPressed: () => h.deletedAt == null ? _del(st, h) : _permanentlyDelete(st, h)),
          ]);
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
              width: isMobile ? 160 : 200,
              child: AntdInput(
                  controller: _searchController,
                  placeholder:
                      Translation.getText(st.locale, 'host.searchPlaceholder'),
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _searchText = v))),
        ], trailing: [
          if (_selectedHostIds.isNotEmpty) ...[
            AntdTag(
              preset: AntdTagPreset.processing,
              label: '${_selectedHostIds.length}',
            ),
            AntdButton(
              size: AntdSize.small,
              onPressed: _batchLoading
                  ? null
                  : () => _confirmBatchAction(st, deploy: true),
              icon: Icons.arrow_circle_down_outlined,
              loading: _batchLoading,
              child: isMobile
                  ? null
                  : Text(st.locale == 'zh' ? '批量部署' : 'Deploy'),
            ),
            AntdButton(
              size: AntdSize.small,
              onPressed: _batchLoading
                  ? null
                  : () => _confirmBatchAction(st, deploy: false),
              icon: Icons.stop_circle_outlined,
              danger: true,
              child: isMobile
                  ? null
                  : Text(st.locale == 'zh' ? '批量停止' : 'Stop'),
            ),
            AntdDropdown<String>(
              tooltip: _text(st, '批量通知设置', 'Batch notifications'),
              items: [
                AntdDropdownItem(
                  value: 'traffic_on',
                  label: _text(st, '启用流量警告', 'Enable traffic alerts'),
                  icon: Icons.notifications_active_outlined,
                ),
                AntdDropdownItem(
                  value: 'traffic_off',
                  label: _text(st, '停用流量警告', 'Disable traffic alerts'),
                  icon: Icons.notifications_off_outlined,
                ),
                AntdDropdownItem(
                  value: 'offline_on',
                  label: _text(st, '启用上下线通知', 'Enable offline alerts'),
                  icon: Icons.wifi_outlined,
                ),
                AntdDropdownItem(
                  value: 'offline_off',
                  label: _text(st, '停用上下线通知', 'Disable offline alerts'),
                  icon: Icons.wifi_off_outlined,
                ),
              ],
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
              child: AntdButton(
                size: AntdSize.small,
                icon: Icons.notifications_outlined,
                onPressed: () {},
              ),
            ),
          ],
          AntdButton(
            size: AntdSize.small,
            type: _showDeleted
                ? AntdButtonType.primary
                : AntdButtonType.defaultType,
            icon: Icons.delete_outline,
            onPressed: () {
              setState(() {
                _showDeleted = !_showDeleted;
                if (!_showDeleted && _quickFilter == 'deleted') {
                  _quickFilter = 'all';
                }
              });
              _loadHosts();
            },
            child: isMobile
                ? null
                : Text(Translation.getText(
                    st.locale,
                    _showDeleted ? 'host.hideDeleted' : 'host.showDeleted',
                  )),
          ),
          AntdButton(
            size: AntdSize.small,
            icon: Icons.refresh,
            loading: _isLoading,
            onPressed: _isLoading ? null : _loadHosts,
          ),
          Tooltip(
            message: canReorder
                ? _text(st, '调整主机顺序', 'Reorder hosts')
                : _text(st, '搜索或筛选时不能排序',
                    'Reordering is disabled while filtering'),
            child: AntdButton(
              size: AntdSize.small,
              icon: Icons.swap_vert,
              onPressed: canReorder ? _showReorderDialog : null,
            ),
          ),
          AntdButton(
              type: AntdButtonType.primary,
              size: AntdSize.small,
              icon: Icons.add,
              onPressed: _add,
              child: isMobile
                  ? null
                  : Text(Translation.getText(st.locale, 'host.addHost'))),
        ]),
        if (_loadError)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: AntdAlert(
              type: AntdAlertType.error,
              message: _text(st, '主机列表加载失败', 'Failed to load hosts'),
              description: _text(
                st,
                '当前显示的可能是旧数据，请重试。',
                'The visible data may be stale. Please retry.',
              ),
              showIcon: true,
              action: AntdButton(
                size: AntdSize.small,
                icon: Icons.refresh,
                onPressed: _isLoading ? null : _loadHosts,
                child: Text(_text(st, '重试', 'Retry')),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: Padding(
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
                        selectable: (host) => host.deletedAt == null,
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
