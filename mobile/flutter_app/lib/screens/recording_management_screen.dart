import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../app/antd_tokens.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

class RecordingManagementScreen extends StatefulWidget {
  const RecordingManagementScreen({super.key});
  @override
  State<RecordingManagementScreen> createState() => _RecordingManagementScreenState();
}

class _RecordingManagementScreenState extends State<RecordingManagementScreen> {
  List<Map<String, dynamic>> _recordings = [];
  bool _isLoading = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await context.read<AppState>().getRecordings();
    if (mounted) setState(() { _recordings = data; _isLoading = false; });
  }

  void _confirmDelete(Map<String, dynamic> rec) {
    final state = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(Translation.getText(state.locale, 'common.confirmDelete')), width: 400, danger: true,
      okText: Translation.getText(state.locale, 'common.confirm'), cancelText: Translation.getText(state.locale, 'common.cancel'),
      onOk: () async { final ok = await state.deleteRecording(rec['id'] as int); if (ok) _load(); },
      child: Text('\u786e\u5b9a\u8981\u5220\u9664 ${rec['filename'] ?? ''} \u5417\uff1f'),
    ));
  }

  void _play(Map<String, dynamic> rec) {
    final state = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Row(children: [
        const Icon(Icons.play_circle_fill, color: AntdTokens.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(rec['filename']??'Playback', overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace'))),
      ]), width: 600, bodyMaxHeight: 400, showFooter: true,
      okText: Translation.getText(state.locale, 'common.close'),
      cancelText: '', onOk: () {},
      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
        color: AntdTokens.isDark(context) ? const Color(0xFF0D0F18) : const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6)),
        child: const Text('\u6b63\u5728\u8fde\u63a5\u4f1a\u8bdd\u56de\u653e...\n\nadmin@termiscope:~\$ neofetch\n  ############      admin@termiscope\n  OS: TermiScope Linux v1.0.4\n  Kernel: x86_64 Linux 5.15.0\n  Uptime: 2 days, 16 hours\n  Shell: bash 5.1.16\n\nadmin@termiscope:~\$ exit\n[\u4f1a\u8bdd\u56de\u653e\u5df2\u5b8c\u6210]',
            style: TextStyle(fontFamily: 'monospace', color: AntdTokens.success, fontSize: 12)),
      ),
    ));
  }

  String _fmtSize(int b) {
    if (b <= 0) return '0 B';
    const s = ['B','KB','MB','GB','TB']; var i=0; double sz=b.toDouble();
    while(sz>=1024&&i<s.length-1){sz/=1024;i++;}
    return '${sz.toStringAsFixed(1)} ${s[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Column(children: [
      AntdToolbar(height: 44, bordered: true, leading: [
        Text(Translation.getText(state.locale, 'recording.terminalRecordings'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ], trailing: [
        AntdButton(icon: Icons.refresh, onPressed: _load),
      ]),
      Expanded(child: _isLoading
        ? const AntdSpin(tip: '\u52a0\u8f7d\u4e2d...')
        : _recordings.isEmpty
          ? AntdEmpty(description: Translation.getText(state.locale, 'sftp.emptyFolder'))
          : ListView.separated(
              itemCount: _recordings.length, padding: const EdgeInsets.all(4),
              separatorBuilder: (_,__) => const SizedBox(height: 4),
              itemBuilder: (_, i) {
                final rec = _recordings[i];
                final sz = rec['size']!=null ? _fmtSize(rec['size'] as int) : '-';
                return AntdCard(child: ListTile(
                  leading: Container(width: 40, height: 40, decoration: BoxDecoration(
                      color: AntdTokens.primary.withAlpha(25), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.videocam, color: AntdTokens.primary)),
                  title: Text(rec['filename']??'recording.cast', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$sz \u2022 ${rec['created_at']??''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    AntdButton(type: AntdButtonType.text, icon: Icons.play_circle_outline, onPressed: ()=>_play(rec)),
                    AntdButton(type: AntdButtonType.text, icon: Icons.delete, danger: true, onPressed: ()=>_confirmDelete(rec)),
                  ]),
                ));
              })),
    ]);
  }
}
