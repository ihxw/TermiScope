import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';

class CommandTemplatesScreen extends StatefulWidget {
  const CommandTemplatesScreen({super.key});
  @override
  State<CommandTemplatesScreen> createState() => _CommandTemplatesScreenState();
}

class _CommandTemplatesScreenState extends State<CommandTemplatesScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchCommandTemplates();
    if (mounted) setState(() => _loading = false);
  }

  void _showEditDialog({var template}) {
    final nameCtrl = TextEditingController(text: template?.name ?? '');
    final cmdCtrl = TextEditingController(text: template?.command ?? '');
    final descCtrl = TextEditingController(text: template?.description ?? '');
    bool autoEnter = template?.autoEnter ?? false;
    final isEdit = template != null;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AntdModal(
                  title: Text(isEdit
                      ? '\u7f16\u8f91\u547d\u4ee4\u6a21\u677f'
                      : '\u65b0\u5efa\u547d\u4ee4\u6a21\u677f'),
                  width: 500,
                  okText: '\u4fdd\u5b58',
                  cancelText: '\u53d6\u6d88',
                  onOk: () async {
                    final name = nameCtrl.text.trim(),
                        cmd = cmdCtrl.text.trim();
                    if (name.isEmpty || cmd.isEmpty) return;
                    if (isEdit) {
                      await context.read<AppState>().updateCommandTemplate(
                            template.id,
                            name,
                            cmd,
                            descCtrl.text.trim(),
                            autoEnter: autoEnter,
                          );
                    } else {
                      await context.read<AppState>().createCommandTemplate(
                            name,
                            cmd,
                            descCtrl.text.trim(),
                            autoEnter: autoEnter,
                          );
                    }
                  },
                  child: Column(children: [
                    AntdFormItem(
                        label: '\u540d\u79f0',
                        required: true,
                        child: AntdInput(
                            controller: nameCtrl, placeholder: '\u540d\u79f0')),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u547d\u4ee4',
                        required: true,
                        child: AntdTextArea(
                            controller: cmdCtrl, minLines: 2, maxLines: 4)),
                    const SizedBox(height: 12),
                    AntdFormItem(
                        label: '\u63cf\u8ff0',
                        child: AntdInput(
                            controller: descCtrl, placeholder: '\u53ef\u9009')),
                    const SizedBox(height: 12),
                    AntdFormItem(
                      label: '自动执行',
                      child: Row(children: [
                        AntdSwitch(
                          value: autoEnter,
                          onChanged: (value) =>
                              setDialogState(() => autoEnter = value),
                        ),
                        const SizedBox(width: 8),
                        Text(autoEnter ? '插入后发送回车' : '仅插入命令'),
                      ]),
                    ),
                  ]),
                )));
  }

  void _confirmDelete(var t) {
    showDialog(
        context: context,
        builder: (_) => AntdModal(
              title: const Text('\u5220\u9664\u547d\u4ee4\u6a21\u677f'),
              width: 400,
              danger: true,
              okText: '\u5220\u9664',
              cancelText: '\u53d6\u6d88',
              onOk: () async {
                await context.read<AppState>().deleteCommandTemplate(t.id);
              },
              child: Text(
                  '\u786e\u5b9a\u8981\u5220\u9664 "${t.name}" \u5417\uff1f'),
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (ctx, state, _) {
      return Column(children: [
        AntdToolbar(height: 44, bordered: true, leading: [
          const Text('\u547d\u4ee4\u6a21\u677f',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ], trailing: [
          AntdButton(
              type: AntdButtonType.primary,
              icon: Icons.add,
              onPressed: () => _showEditDialog(),
              child: const Text('\u65b0\u5efa')),
        ]),
        Expanded(
            child: _loading
                ? const AntdSpin(tip: '\u52a0\u8f7d\u4e2d...')
                : state.commandTemplates.isEmpty
                    ? const AntdEmpty(
                        description:
                            '\u6682\u65e0\u547d\u4ee4\u6a21\u677f\n\u70b9\u51fb\u65b0\u5efa')
                    : ListView.separated(
                        itemCount: state.commandTemplates.length,
                        separatorBuilder: (_, __) => Container(
                            height: 1,
                            color: AntdTokens.borderSecondaryColor(ctx)),
                        itemBuilder: (_, i) {
                          final t = state.commandTemplates[i];
                          return ListTile(
                            leading: const Icon(Icons.code,
                                color: AntdTokens.primary, size: 20),
                            title: Text(t.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            isThreeLine: t.description.isNotEmpty,
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(t.command,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: AntdTokens.primary)),
                                  if (t.description.isNotEmpty)
                                    Text(t.description,
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 10)),
                                  const SizedBox(height: 3),
                                  AntdTag(
                                    preset: t.autoEnter
                                        ? AntdTagPreset.success
                                        : AntdTagPreset.defaultStyle,
                                    label: t.autoEnter ? '自动执行' : '仅插入',
                                  ),
                                ]),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              AntdButton(
                                  type: AntdButtonType.text,
                                  icon: Icons.copy,
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: t.command));
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                            content: Text('\u5df2\u590d\u5236'),
                                            duration: Duration(seconds: 1)));
                                  }),
                              AntdButton(
                                  type: AntdButtonType.text,
                                  icon: Icons.edit,
                                  onPressed: () =>
                                      _showEditDialog(template: t)),
                              AntdButton(
                                  type: AntdButtonType.text,
                                  icon: Icons.delete,
                                  danger: true,
                                  onPressed: () => _confirmDelete(t)),
                            ]),
                          );
                        })),
      ]);
    });
  }
}
