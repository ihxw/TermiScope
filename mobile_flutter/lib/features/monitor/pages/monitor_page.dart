import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/hosts_provider.dart';
import '../widgets/host_card.dart';

class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> {
  @override
  void initState() {
    super.initState();
    // 加载数据并连接 WebSocket
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(hostsStateProvider.notifier).loadHosts();
      ref.read(hostsStateProvider.notifier).connectWebSocket();
    });
  }

  @override
  void dispose() {
    // 断开 WebSocket
    ref.read(hostsStateProvider.notifier).disconnectWebSocket();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await ref.read(hostsStateProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hostsStateProvider);
    final hosts = state.hostsWithMonitorData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('监控中心'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _onRefresh,
          ),
        ],
      ),
      body: state.isLoading && hosts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && hosts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '加载失败',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _onRefresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : hosts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.dns_outlined,
                            size: 64,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无主机',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => context.go('/hosts'),
                            icon: const Icon(Icons.add),
                            label: const Text('添加主机'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: hosts.length,
                        itemBuilder: (context, index) {
                          final host = hosts[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: HostCard(
                              host: host,
                              onTap: () {
                                // 跳转到终端
                                context.push('/terminal/${host.id}');
                              },
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
