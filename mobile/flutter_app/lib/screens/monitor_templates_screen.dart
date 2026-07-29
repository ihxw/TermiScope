import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/antd_tokens.dart';
import '../providers/app_state.dart';
import '../widgets/antd/index.dart';

class MonitorTemplatesScreen extends StatefulWidget {
  const MonitorTemplatesScreen({super.key});

  @override
  State<MonitorTemplatesScreen> createState() => _MonitorTemplatesScreenState();
}

class _MonitorTemplatesScreenState extends State<MonitorTemplatesScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    final state = context.read<AppState>();
    final data = await state.getNetworkTemplates();
    if (mounted) {
      setState(() {
        _templates = data;
        _isLoading = false;
      });
    }
  }

  void _openAddModal() {
    _showEditModal(null);
  }

  void _showEditModal(Map<String, dynamic>? template) {
    final isEdit = template != null;
    final nameCtrl = TextEditingController(text: template?['name'] ?? '');
    final targetCtrl = TextEditingController(text: template?['target'] ?? '');
    final portCtrl =
        TextEditingController(text: (template?['port'] ?? 80).toString());
    final labelCtrl = TextEditingController(text: template?['label'] ?? '');
    final freqCtrl =
        TextEditingController(text: (template?['frequency'] ?? 60).toString());
    final colorCtrl =
        TextEditingController(text: template?['color'] ?? '#1890ff');

    String selectedType = template?['type'] ?? 'ping';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return AntdModal(
              title: Text(isEdit ? '编辑监控模板' : '添加监控模板'),
              width: 500,
              okText: '确认',
              cancelText: '取消',
              onOk: () async {
                final name = nameCtrl.text.trim();
                final target = targetCtrl.text.trim();
                final label = labelCtrl.text.trim();
                final freq = int.tryParse(freqCtrl.text.trim()) ?? 60;
                final port = int.tryParse(portCtrl.text.trim()) ?? 80;
                final color = colorCtrl.text.trim();

                if (name.isEmpty || target.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('模板名称和目标地址为必填项')),
                  );
                  return;
                }

                final state = dialogContext.read<AppState>();
                final payload = {
                  'name': name,
                  'type': selectedType,
                  'target': target,
                  'port': port,
                  'label': label,
                  'frequency': freq,
                  'color': color,
                };

                bool ok;
                if (isEdit) {
                  ok = await state.updateNetworkTemplate(
                      template['id'] as int, payload);
                } else {
                  ok = await state.createNetworkTemplate(payload);
                }

                if (ok) {
                  if (!mounted || !dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(isEdit ? '模板更新成功' : '模板添加成功'),
                        backgroundColor: AntdTokens.success),
                  );
                  _loadTemplates();
                } else {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content: Text('操作失败'),
                          backgroundColor: AntdTokens.error),
                    );
                  }
                }
              },
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AntdFormItem(
                        label: '模板名称',
                        required: true,
                        child: AntdInput(
                            controller: nameCtrl,
                            placeholder: 'e.g. Google DNS'),
                      ),
                      const SizedBox(height: 12),
                      AntdFormItem(
                        label: '检测类型',
                        required: true,
                        child: AntdSelect<String>(
                          value: selectedType,
                          options: const [
                            AntdSelectOption(
                                value: 'ping', label: 'Ping (ICMP)'),
                            AntdSelectOption(
                                value: 'tcping', label: 'TCPing (Port)'),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => selectedType = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      AntdFormItem(
                        label: '目标地址',
                        required: true,
                        child: AntdInput(
                            controller: targetCtrl,
                            placeholder: 'e.g. 8.8.8.8'),
                      ),
                      const SizedBox(height: 12),
                      if (selectedType == 'tcping') ...[
                        AntdFormItem(
                          label: '目标端口',
                          required: true,
                          child: AntdInput(
                              controller: portCtrl,
                              keyboardType: TextInputType.number),
                        ),
                        const SizedBox(height: 12),
                      ],
                      AntdFormItem(
                        label: '标签 (选填)',
                        child: AntdInput(
                            controller: labelCtrl, placeholder: 'e.g. DNS'),
                      ),
                      const SizedBox(height: 12),
                      AntdFormItem(
                        label: '检测频率 (秒)',
                        child: AntdInput(
                            controller: freqCtrl,
                            keyboardType: TextInputType.number),
                      ),
                      const SizedBox(height: 12),
                      AntdFormItem(
                        label: '图表颜色',
                        child: Row(children: [
                          Expanded(
                            child: AntdInput(
                                controller: colorCtrl, placeholder: '#1890ff'),
                          ),
                          const SizedBox(width: 8),
                          // Simple preset colors
                          ...[
                            '#F44336',
                            '#4CAF50',
                            '#1890ff',
                            '#FFC107'
                          ].map((c) => GestureDetector(
                                onTap: () {
                                  setModalState(() => colorCtrl.text = c);
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  margin: const EdgeInsets.only(left: 4),
                                  decoration: BoxDecoration(
                                    color: Color(
                                        int.parse(c.replaceFirst('#', '0xFF'))),
                                    border: Border.all(
                                        color: Colors.grey, width: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              )),
                        ]),
                      ),
                    ]),
              ),
            );
          },
        );
      },
    );
  }

  void _deleteTemplate(int id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AntdModal(
        title: const Text('删除确认'),
        danger: true,
        okText: '确认删除',
        cancelText: '取消',
        onOk: () async {
          final state = context.read<AppState>();
          final ok = await state.deleteNetworkTemplate(id);
          if (ok) {
            if (!mounted || !dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('模板已删除'), backgroundColor: AntdTokens.success),
            );
            _loadTemplates();
          } else {
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                    content: Text('删除失败'), backgroundColor: AntdTokens.error),
              );
            }
          }
        },
        child: const Text('确定要删除此监控模板吗？这会清除其所有关联的检测任务。'),
      ),
    );
  }

  Future<void> _openApplyModal(Map<String, dynamic> template) async {
    final state = context.read<AppState>();
    final templateId = template['id'] as int;

    // Load assigned host IDs from API
    List<int> assignedHostIds = [];
    try {
      final res = await state.apiService
          .get('/api/monitor/network/templates/$templateId/assignments');
      if (res is List) {
        assignedHostIds = res.whereType<num>().map((id) => id.toInt()).toList();
      }
    } catch (e) {
      debugPrint('Load template assignments error: $e');
    }

    final Set<int> selectedHostIds = Set<int>.from(assignedHostIds);
    final sshHosts =
        state.hosts.where((h) => h.hostType != 'monitor_only').toList();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            return AntdModal(
              title: Text('部署模板 - ${template['name']}'),
              width: 500,
              okText: '确认部署',
              cancelText: '取消',
              onOk: sshHosts.isEmpty
                  ? null
                  : () async {
                      final ok = await state.batchApplyNetworkTemplate(
                          templateId, selectedHostIds.toList());
                      if (ok) {
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('模板已成功部署到选定主机'),
                              backgroundColor: AntdTokens.success),
                        );
                      } else {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                                content: Text('部署失败'),
                                backgroundColor: AntdTokens.error),
                          );
                        }
                      }
                    },
              child: SizedBox(
                height: 300,
                width: double.maxFinite,
                child: sshHosts.isEmpty
                    ? const Center(child: AntdEmpty(description: '没有可用主机'))
                    : ListView.builder(
                        itemCount: sshHosts.length,
                        itemBuilder: (context, index) {
                          final h = sshHosts[index];
                          final isSelected = selectedHostIds.contains(h.id);
                          return CheckboxListTile(
                            title: Text(h.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('${h.host}:${h.port}'),
                            value: isSelected,
                            activeColor: AntdTokens.primary,
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selectedHostIds.add(h.id);
                                } else {
                                  selectedHostIds.remove(h.id);
                                }
                              });
                            },
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

  @override
  Widget build(BuildContext context) {
    final border = AntdTokens.borderSecondaryColor(context);
    final columns = <AntdTableColumn<Map<String, dynamic>>>[
      AntdTableColumn(
        title: '模板名称',
        width: 150,
        cell: (ctx, row, _) => Text(row['name'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      AntdTableColumn(
        title: '检测类型',
        width: 100,
        cell: (ctx, row, _) {
          final t = (row['type']?.toString() ?? 'ping').toUpperCase();
          return AntdTag(preset: AntdTagPreset.processing, label: t);
        },
      ),
      AntdTableColumn(
        title: '目标地址',
        width: 180,
        cell: (ctx, row, _) {
          final target = row['target']?.toString() ?? '';
          final port = row['port']?.toString() ?? '';
          final isTcp = row['type']?.toString() == 'tcping';
          return Text(isTcp ? '$target:$port' : target);
        },
      ),
      AntdTableColumn(
        title: '检测频率',
        width: 100,
        cell: (ctx, row, _) => Text('${row['frequency'] ?? 60} 秒'),
      ),
      AntdTableColumn(
        title: '操作',
        width: 160,
        cell: (ctx, row, _) => Row(children: [
          TextButton(
            onPressed: () => _showEditModal(row),
            child: const Text('编辑', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _openApplyModal(row),
            child: const Text('部署', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () => _deleteTemplate(row['id'] as int),
            child: const Text('删除',
                style: TextStyle(color: AntdTokens.error, fontSize: 12)),
          ),
        ]),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('监控模板管理'),
        backgroundColor: AntdTokens.containerColor(context),
        foregroundColor: AntdTokens.textColor(context),
        elevation: 0,
      ),
      body: Container(
        color: AntdTokens.pageColor(context),
        child: Column(children: [
          AntdToolbar(
            height: 48,
            bordered: true,
            leading: [
              AntdButton(
                type: AntdButtonType.primary,
                icon: Icons.add,
                onPressed: _openAddModal,
                child: const Text('添加模板'),
              ),
            ],
            trailing: [
              AntdButton(icon: Icons.refresh, onPressed: _loadTemplates),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AntdTokens.containerColor(context),
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
                ),
                clipBehavior: Clip.antiAlias,
                child: _isLoading
                    ? const Center(child: AntdSpin(tip: '加载模板中...'))
                    : AntdTable<Map<String, dynamic>>(
                        rowKey: (row) => row['id']?.toString() ?? '',
                        columns: columns,
                        data: _templates,
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
