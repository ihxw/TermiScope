import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _loading = true;
  final _cur = TextEditingController(), _nw = TextEditingController(), _cf = TextEditingController();

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); _cur.dispose(); _nw.dispose(); _cf.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchProfile();
    await context.read<AppState>().fetchLoginHistory();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _changePass(AppState s) async {
    if (_nw.text != _cf.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u4e24\u6b21\u8f93\u5165\u7684\u65b0\u5bc6\u7801\u4e0d\u4e00\u81f4')));
      return;
    }
    final ok = await s.changePassword(_cur.text, _nw.text);
    if (ok) { _cur.clear(); _nw.clear(); _cf.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u5bc6\u7801\u4fee\u6539\u6210\u529f'))); }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (ctx, s, _) => Scaffold(
      appBar: AppBar(title: const Text('\u4e2a\u4eba\u8d44\u6599'), actions: [
        Padding(padding: const EdgeInsets.only(right: 8),
            child: AntdButton(type: AntdButtonType.text, icon: Icons.refresh, onPressed: _loading ? null : _load)),
      ], bottom: TabBar(controller: _tab, tabs: const [
        Tab(text: '\u5b89\u5168', icon: Icon(Icons.lock, size: 16)),
        Tab(text: '\u4f1a\u8bdd', icon: Icon(Icons.devices, size: 16)),
      ])),
      body: _loading ? const AntdSpin() : TabBarView(controller: _tab, children: [_security(s), _sessions(s)]),
    ));
  }

  Widget _security(AppState s) {
    final p = s.profile;
    return ListView(padding: EdgeInsets.all(AntdTokens.cardBodyPadding(context)), children: [
      if (p != null) ...[
        Row(children: [
          CircleAvatar(radius: 28, backgroundColor: AntdTokens.primary,
              child: Text(p.username.isNotEmpty?p.username[0].toUpperCase():'?',
                  style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.w600))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            if (p.email.isNotEmpty) Text(p.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text(p.role == 'admin' ? '\u7ba1\u7406\u5458' : '\u666e\u901a\u7528\u6237',
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 8),
        AntdStatusBadge(
          status: p.twoFactorEnabled ? AntdStatusBadgeStatus.success : AntdStatusBadgeStatus.defaultStatus,
          text: p.twoFactorEnabled ? '\u4e24\u6b65\u9a8c\u8bc1\u5df2\u542f\u7528' : '\u4e24\u6b65\u9a8c\u8bc1\u672a\u542f\u7528'),
      ],
      const SizedBox(height: 12),
      const AntdDivider(text: '\u4fee\u6539\u5bc6\u7801'),
      const SizedBox(height: 8),
      AntdFormItem(label: '\u5f53\u524d\u5bc6\u7801', child: AntdPasswordInput(controller: _cur)),
      const SizedBox(height: 12),
      AntdFormItem(label: '\u65b0\u5bc6\u7801', child: AntdPasswordInput(controller: _nw)),
      const SizedBox(height: 12),
      AntdFormItem(label: '\u786e\u8ba4\u65b0\u5bc6\u7801', child: AntdPasswordInput(controller: _cf)),
      const SizedBox(height: 12),
      AntdButton(type: AntdButtonType.primary, block: true, onPressed: () => _changePass(s), child: const Text('\u4fee\u6539\u5bc6\u7801')),
      const SizedBox(height: 8),
      const Text('\u63d0\u793a\uff1a\u4fee\u6539\u5bc6\u7801\u540e\uff0c\u8bf7\u91cd\u65b0\u767b\u5f55\u3002', style: TextStyle(color: Colors.grey, fontSize: 11)),
    ]);
  }

  Widget _sessions(AppState s) {
    if (s.loginSessions.isEmpty) return const AntdEmpty(description: '\u6682\u65e0\u767b\u5f55\u8bb0\u5f55');
    return ListView.separated(
      itemCount: s.loginSessions.length,
      separatorBuilder: (_,__) => Container(height: 1, color: AntdTokens.borderSecondaryColor(context)),
      itemBuilder: (_, i) {
        final h = s.loginSessions[i];
        return ListTile(
          leading: Icon(Icons.devices, color: AntdTokens.primary),
          title: Text(h.ipAddress, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(h.loginAt.toString()),
          trailing: AntdTag(preset: AntdTagPreset.processing, label: h.status),
        );
      },
    );
  }
}
