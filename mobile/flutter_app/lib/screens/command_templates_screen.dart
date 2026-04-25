import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';

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
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchCommandTemplates();
    if (mounted) setState(() => _loading = false);
  }

  void _showEditDialog({CommandTemplate? template}) {
    final nameCtrl = TextEditingController(text: template?.name ?? '');
    final cmdCtrl = TextEditingController(text: template?.command ?? '');
    final descCtrl = TextEditingController(text: template?.description ?? '');
    final isEdit = template != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(isEdit ? '编辑命令模板' : '新建命令模板'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  hintText: '名称',
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cmdCtrl,
                decoration: const InputDecoration(
                  hintText: '命令',
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  hintText: '描述 (可选)',
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final cmd = cmdCtrl.text.trim();
              if (name.isEmpty || cmd.isEmpty) return;
              if (isEdit) {
                await context.read<AppState>().updateCommandTemplate(
                    template.id, name, cmd, descCtrl.text.trim());
              } else {
                await context.read<AppState>().createCommandTemplate(
                    name, cmd, descCtrl.text.trim());
              }
              if (mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64D2FF)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('命令模板'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showEditDialog(),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : state.commandTemplates.isEmpty
                  ? const Center(
                      child: Text('暂无命令模板\n点击 + 新建',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: state.commandTemplates.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFF2D2D2D)),
                      itemBuilder: (context, index) {
                        final t = state.commandTemplates[index];
                        return ListTile(
                          leading: const Icon(Icons.code,
                              color: Color(0xFF64D2FF), size: 20),
                          title: Text(t.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(t.command,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Color(0xFF64D2FF))),
                              if (t.description.isNotEmpty)
                                Text(t.description,
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 10)),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon:
                                    const Icon(Icons.copy, size: 18),
                                tooltip: '复制',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(
                                      text: t.command));
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                          content: Text('已复制到剪贴板'),
                                          duration: Duration(seconds: 1)));
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _showEditDialog(template: t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 18, color: Colors.red),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor:
                                          const Color(0xFF2D2D2D),
                                      title: const Text('删除命令模板'),
                                      content:
                                          Text('确定要删除 "${t.name}" 吗？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx),
                                          child: const Text('取消'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () async {
                                            await context
                                                .read<AppState>()
                                                .deleteCommandTemplate(
                                                    t.id);
                                            if (context.mounted) {
                                              Navigator.pop(ctx);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.red),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
