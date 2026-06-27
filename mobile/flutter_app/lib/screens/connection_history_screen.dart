import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';

class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key});
  @override
  State<ConnectionHistoryScreen> createState() => _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  bool _loading = true;
  int? _selectedHostId;

  @override
  void initState() { super.initState(); _loadLogs(); }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchConnectionLogs(hostId: _selectedHostId);
    if (mounted) setState(() => _loading = false);
  }

  String _fmtDuration(int s) {
    if (s == 0) return '--';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }
  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (ctx, state, _) {
      final hostOpts = [const AntdSelectOption<int?>(value: null, label: '\u5168\u90e8')] +
          state.hosts.map((h) => AntdSelectOption<int?>(value: h.id, label: h.name)).toList();

      return Column(children: [
        AntdToolbar(height: 44, bordered: true, leading: [
          const Text('\u8fde\u63a5\u5386\u53f2', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ], trailing: [
          SizedBox(width: 200, child: AntdSelect<int?>(value: _selectedHostId, placeholder: '\u5168\u90e8',
            options: hostOpts, onChanged: (v) { setState(() { _selectedHostId = v; state.connectionLogsPage = 1; }); _loadLogs(); })),
          Text('\u5171 ${state.connectionLogsTotal} \u6761', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          AntdButton(icon: Icons.refresh, onPressed: _loading ? null : _loadLogs),
        ]),
        Expanded(child: _loading
          ? const AntdSpin(tip: '\u52a0\u8f7d\u4e2d...')
          : state.connectionLogs.isEmpty
            ? const AntdEmpty(description: '\u6682\u65e0\u8fde\u63a5\u8bb0\u5f55')
            : ListView.separated(
                itemCount: state.connectionLogs.length,
                separatorBuilder: (_,__) => Container(height:1,color:AntdTokens.borderSecondaryColor(ctx)),
                itemBuilder: (_, i) {
                  final log = state.connectionLogs[i];
                  final sc = log.status == 'success' ? AntdTokens.success
                      : log.status == 'failed' ? AntdTokens.error : AntdTokens.warning;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: sc.withAlpha(50),
                        child: Icon(log.status=='success'?Icons.login:Icons.warning_amber, color:sc, size:18)),
                    title: Text(log.sshHostName ?? log.host, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 4),
                      Text('${log.username}@${log.host}:${log.port} \u2022 ${_fmtDate(log.connectedAt)}',
                          style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      if (log.errorMessage != null)
                        Text('\u9519\u8bef: ${log.errorMessage}', style: const TextStyle(color: Colors.red, fontSize: 10)),
                    ]),
                    trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end, children: [
                      AntdTag(color: sc, label: log.status),
                      const SizedBox(height: 4),
                      Text(_fmtDuration(log.duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ]),
                  );
                })),
      ]);
    });
  }
}
