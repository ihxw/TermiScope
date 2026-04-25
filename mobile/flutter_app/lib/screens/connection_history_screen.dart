import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key});

  @override
  State<ConnectionHistoryScreen> createState() => _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  bool _loading = true;
  int? _selectedHostId;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    await context.read<AppState>().fetchConnectionLogs(hostId: _selectedHostId);
    if (mounted) setState(() => _loading = false);
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('连接历史'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _loadLogs,
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : state.connectionLogs.isEmpty
                  ? const Center(child: Text('暂无连接记录', style: TextStyle(color: Colors.grey)))
                  : Column(
                      children: [
                        // Host filter row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Text('主机: ', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              Expanded(
                                child: DropdownButton<int?>(
                                  isExpanded: true,
                                  value: _selectedHostId,
                                  hint: const Text('全部', style: TextStyle(fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem<int?>(value: null, child: Text('全部', style: TextStyle(fontSize: 13))),
                                    ...state.hosts.map((h) => DropdownMenuItem<int?>(
                                          value: h.id,
                                          child: Text(h.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                        )),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedHostId = val;
                                      state.connectionLogsPage = 1;
                                    });
                                    _loadLogs();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '共 ${state.connectionLogsTotal} 条',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFF2D2D2D)),
                        // Log list
                        Expanded(
                          child: ListView.separated(
                            itemCount: state.connectionLogs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF2D2D2D)),
                            itemBuilder: (context, index) {
                              final log = state.connectionLogs[index];
                              final statusColor = log.status == 'success'
                                  ? const Color(0xFF32D74B)
                                  : log.status == 'failed'
                                      ? Colors.red
                                      : Colors.orange;
                              final hostLabel = log.sshHostName ?? log.host;

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: statusColor.withAlpha(51),
                                  child: Icon(
                                    log.status == 'success'
                                        ? Icons.login
                                        : Icons.warning_amber,
                                    color: statusColor,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  hostLabel,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      '${log.username}@${log.host}:${log.port}  •  ${_formatDate(log.connectedAt)}',
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                    if (log.errorMessage != null)
                                      Text(
                                        '错误: ${log.errorMessage}',
                                        style: const TextStyle(color: Colors.red, fontSize: 10),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withAlpha(51),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        log.status,
                                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDuration(log.duration),
                                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}
