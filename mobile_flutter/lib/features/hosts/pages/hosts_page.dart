import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/hosts_provider.dart';
import '../../../core/models/ssh_host.dart';
import '../../../shared/theme/app_theme.dart';

class HostsPage extends ConsumerStatefulWidget {
  const HostsPage({super.key});

  @override
  ConsumerState<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends ConsumerState<HostsPage> {
  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(hostsStateProvider.notifier).loadHosts();
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIds.clear();
      }
    });
  }

  void _toggleHostSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchDeploy() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量部署监控'),
        content: Text('确定要为 ${_selectedIds.length} 台主机部署监控吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(hostsStateProvider.notifier).batchDeployMonitor(
            _selectedIds.toList(),
          );
      _toggleSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('批量部署任务已启动')),
        );
      }
    }
  }

  Future<void> _batchStop() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量停止监控'),
        content: Text('确定要停止 ${_selectedIds.length} 台主机的监控吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(hostsStateProvider.notifier).batchStopMonitor(
            _selectedIds.toList(),
          );
      _toggleSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('批量停止任务已执行')),
        );
      }
    }
  }

  Future<void> _deleteHost(SshHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除主机'),
        content: Text('确定要删除主机 "${host.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(hostsStateProvider.notifier).deleteHost(host.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主机已删除')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hostsStateProvider);
    final hosts = state.hosts;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? '已选择 ${_selectedIds.length} 项' : '主机管理'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: '批量部署',
              onPressed: _selectedIds.isNotEmpty ? _batchDeploy : null,
            ),
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: '批量停止',
              onPressed: _selectedIds.isNotEmpty ? _batchStop : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: hosts.isNotEmpty ? _toggleSelectionMode : null,
            ),
          ],
        ],
      ),
      body: state.isLoading && hosts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : hosts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dns_outlined,
                          size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text('暂无主机',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(hostsStateProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: hosts.length,
                    itemBuilder: (context, index) {
                      final host = hosts[index];
                      final isSelected = _selectedIds.contains(host.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) =>
                                      _toggleHostSelection(host.id),
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.primaryColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.dns,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                          title: Text(host.name),
                          subtitle: Text(
                            '${host.host}:${host.port}',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: host.monitorEnabled
                                      ? AppTheme.successColor.withOpacity(0.2)
                                      : Colors.grey.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  host.monitorEnabled ? '监控中' : '未监控',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: host.monitorEnabled
                                        ? AppTheme.successColor
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'terminal':
                                      context.push('/terminal/${host.id}');
                                      break;
                                    case 'edit':
                                      context.go('/hosts/${host.id}/edit');
                                      break;
                                    case 'deploy':
                                      ref
                                          .read(hostsStateProvider.notifier)
                                          .deployMonitor(host.id);
                                      break;
                                    case 'stop':
                                      ref
                                          .read(hostsStateProvider.notifier)
                                          .stopMonitor(host.id);
                                      break;
                                    case 'delete':
                                      _deleteHost(host);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'terminal',
                                    child: Row(
                                      children: [
                                        Icon(Icons.terminal,
                                            size: 20,
                                            color: AppTheme.primaryColor),
                                        SizedBox(width: 8),
                                        Text('SSH终端',
                                            style: TextStyle(
                                                color: AppTheme.primaryColor)),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 8),
                                        Text('编辑'),
                                      ],
                                    ),
                                  ),
                                  if (!host.monitorEnabled)
                                    const PopupMenuItem(
                                      value: 'deploy',
                                      child: Row(
                                        children: [
                                          Icon(Icons.play_arrow, size: 20),
                                          SizedBox(width: 8),
                                          Text('部署监控'),
                                        ],
                                      ),
                                    )
                                  else
                                    const PopupMenuItem(
                                      value: 'stop',
                                      child: Row(
                                        children: [
                                          Icon(Icons.stop, size: 20),
                                          SizedBox(width: 8),
                                          Text('停止监控'),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete,
                                            size: 20,
                                            color: AppTheme.errorColor),
                                        SizedBox(width: 8),
                                        Text('删除',
                                            style: TextStyle(
                                                color: AppTheme.errorColor)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: _isSelectionMode
                              ? () => _toggleHostSelection(host.id)
                              : () => context.go('/hosts/${host.id}/edit'),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/hosts/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
