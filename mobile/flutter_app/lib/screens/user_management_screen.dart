import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../app/antd_tokens.dart';
import '../utils/translation.dart';
import '../widgets/antd/index.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data = await context.read<AppState>().getUsers();
    if (mounted) setState(() { _users = data; _isLoading = false; });
  }

  void _showEditDialog([Map<String, dynamic>? u]) {
    final isEdit = u != null;
    final uname = TextEditingController(text: isEdit ? u['username'] : '');
    final pass = TextEditingController();
    final disp = TextEditingController(text: isEdit ? u['display_name'] : '');
    final email = TextEditingController(text: isEdit ? u['email'] : '');
    String role = isEdit ? (u['role'] ?? 'user') : 'user';
    final st = context.read<AppState>();
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setDlg) => AntdModal(
      title: Text(isEdit ? Translation.getText(st.locale,'user.editUser') : Translation.getText(st.locale,'user.addUser')), width: 480,
      okText: Translation.getText(st.locale,'common.confirm'), cancelText: Translation.getText(st.locale,'common.cancel'),
      onOk: () async {
        final name = uname.text.trim(), pw = pass.text.trim();
        if (name.isEmpty || (!isEdit && pw.isEmpty)) return;
        final d = {'username':name, if (!isEdit) 'password':pw, 'display_name':disp.text.trim(), 'email':email.text.trim(), 'role':role};
        final ok = isEdit ? await st.updateUser(u['id'] as int, d) : await st.createUser(d);
        if (ok) _load();
      },
      child: Column(children: [
        AntdFormItem(label: Translation.getText(st.locale,'user.username'), required: true,
            child: AntdInput(controller: uname, enabled: !isEdit)),
        const SizedBox(height: 12),
        if (!isEdit) AntdFormItem(label: Translation.getText(st.locale,'auth.password'), required: true,
            child: AntdPasswordInput(controller: pass)),
        if (!isEdit) const SizedBox(height: 12),
        AntdFormItem(label: Translation.getText(st.locale,'user.displayName'), child: AntdInput(controller: disp)),
        const SizedBox(height: 12),
        AntdFormItem(label: Translation.getText(st.locale,'user.email'),
            child: AntdInput(controller: email, keyboardType: TextInputType.emailAddress)),
        const SizedBox(height: 12),
        AntdFormItem(label: Translation.getText(st.locale,'user.role'),
            child: AntdSelect<String>(value: role, options: const [
              AntdSelectOption(value: 'admin', label: '\u7ba1\u7406\u5458'),
              AntdSelectOption(value: 'user', label: '\u666e\u901a\u7528\u6237'),
            ], onChanged: (v) { if (v != null) setDlg(() => role = v); })),
      ]),
    )));
  }

  void _del(Map<String, dynamic> u) {
    final st = context.read<AppState>();
    showDialog(context: context, builder: (_) => AntdModal(
      title: Text(Translation.getText(st.locale,'common.confirmDelete')), width: 400, danger: true,
      okText: Translation.getText(st.locale,'common.confirm'), cancelText: Translation.getText(st.locale,'common.cancel'),
      onOk: () async { final ok = await st.deleteUser(u['id'] as int); if (ok) _load(); },
      child: Text('\u786e\u5b9a\u8981\u5220\u9664 ${u['username']} \u5417\uff1f'),
    ));
  }

  Future<void> _resetPw(Map<String, dynamic> u) async {
    final ok = await context.read<AppState>().resetUserPassword(u['id'] as int);
    if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('\u5bc6\u7801\u5df2\u91cd\u7f6e')));
  }

  Future<void> _toggle(Map<String, dynamic> u, bool cur) async {
    final ok = await context.read<AppState>().toggleUserStatus(u['id'] as int, !cur);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = Provider.of<AppState>(context);
    final cols = <AntdTableColumn<Map<String, dynamic>>>[
      AntdTableColumn(title: Translation.getText(st.locale,'user.username'), width: 130,
        cell: (ctx, u, _) => Row(children: [
          CircleAvatar(radius: 12, backgroundColor: (u['role']=='admin'?AntdTokens.primary:Colors.grey).withAlpha(40),
              child: Icon(u['role']=='admin'?Icons.admin_panel_settings:Icons.person, size: 14,
                  color: u['role']=='admin'?AntdTokens.primary:Colors.grey)),
          const SizedBox(width: 8),
          Expanded(child: Text(u['username']??'', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
      AntdTableColumn(title: '\u89d2\u8272', width: 70,
        cell: (ctx, u, _) => AntdTag(
          preset: u['role']=='admin'?AntdTagPreset.processing:AntdTagPreset.defaultStyle,
          label: u['role']=='admin'?'\u7ba1\u7406\u5458':'\u666e\u901a\u7528\u6237'),
      ),
      AntdTableColumn(title: Translation.getText(st.locale,'user.displayName'), width: 100,
        cell: (ctx, u, _) => Text(u['display_name']??'', overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AntdTokens.fontSizeSM, color: AntdTokens.secondaryTextColor(ctx))),
      ),
      AntdTableColumn(title: Translation.getText(st.locale,'user.email'), width: 150,
        cell: (ctx, u, _) => Text(u['email']??'', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AntdTokens.fontSizeSM)),
      ),
      AntdTableColumn(title: '\u72b6\u6001', width: 60,
        cell: (ctx, u, _) {
          final active = u['is_active']==true || u['status']=='active';
          return AntdSwitch(value: active, color: AntdTokens.success, onChanged: (v) => _toggle(u, active));
        },
      ),
      AntdTableColumn(title: '\u64cd\u4f5c', width: 50,
        cell: (ctx, u, _) => AntdActionMenu(items: [
          const AntdActionMenuItem(key: 'edit', label: '\u7f16\u8f91', icon: Icons.edit),
          const AntdActionMenuItem(key: 'reset', label: '\u91cd\u7f6e\u5bc6\u7801', icon: Icons.lock_reset),
          const AntdActionMenuItem(key: 'delete', label: '\u5220\u9664', icon: Icons.delete, danger: true),
        ], onAction: (k) => switch (k) {
          'edit' => _showEditDialog(u), 'reset' => _resetPw(u), 'delete' => _del(u), _ => null,
        }),
      ),
    ];

    return Column(children: [
      AntdToolbar(height: 44, bordered: true, leading: [
        Text(Translation.getText(st.locale,'user.title'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ], trailing: [
        AntdButton(icon: Icons.refresh, onPressed: _load),
        AntdButton(type: AntdButtonType.primary, icon: Icons.add, onPressed: () => _showEditDialog(),
            child: Text(Translation.getText(st.locale,'user.addUser'))),
      ]),
      Expanded(child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AntdTokens.contentPadding(context)),
        child: Container(decoration: BoxDecoration(color: AntdTokens.containerColor(context),
            borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
            border: Border.all(color: AntdTokens.borderSecondaryColor(context))),
          clipBehavior: Clip.antiAlias,
          child: AntdTable<Map<String, dynamic>>(
            rowKey: (u) => u['id'].toString(), loading: _isLoading, data: _users, columns: cols,
            emptyWidget: const AntdEmpty(description: '\u6682\u65e0\u7528\u6237'),
          ))),
      ),
    ]);
  }
}
