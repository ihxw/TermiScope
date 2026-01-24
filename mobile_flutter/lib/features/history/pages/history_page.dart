import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/theme/app_theme.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/connection-logs');

      setState(() {
        _logs = List<Map<String, dynamic>>.from(response ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history,
                          size: 64, color: Colors.grey.shade600),
                      const SizedBox(height: 16),
                      Text(
                        '暂无连接历史',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return _buildLogItem(log);
                    },
                  ),
                ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final status = log['status'] ?? 'unknown';
    final isSuccess = status == 'success';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isSuccess ? AppTheme.successColor : AppTheme.errorColor)
                .withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSuccess ? Icons.check_circle : Icons.error,
            color: isSuccess ? AppTheme.successColor : AppTheme.errorColor,
          ),
        ),
        title: Text(log['host'] ?? 'Unknown'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${log['username'] ?? ''}@${log['host'] ?? ''}:${log['port'] ?? 22}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            Text(
              '${_formatDate(log['connected_at'])} ${log['duration'] != null ? '· ${_formatDuration(log['duration'])}' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      return '${seconds ~/ 3600}小时${(seconds % 3600) ~/ 60}分钟';
    } else if (seconds >= 60) {
      return '${seconds ~/ 60}分钟';
    } else {
      return '$seconds秒';
    }
  }
}
