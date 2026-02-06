import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/api_service.dart';
import '../../data/services/log_service.dart';
import 'package:mobile/l10n/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late LogService _logService;

  List<dynamic> _sshLogs = [];
  bool _sshLoading = false;

  List<dynamic> _loginLogs = [];
  bool _loginLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _logService = LogService(Provider.of<ApiService>(context, listen: false));

    _loadSSHLogs();
    _loadLoginLogs();
  }

  Future<void> _loadSSHLogs() async {
    setState(() => _sshLoading = true);
    try {
      final logs = await _logService.getConnectionLogs(1, 50);
      if (mounted) setState(() => _sshLogs = logs);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _sshLoading = false);
    }
  }

  Future<void> _loadLoginLogs() async {
    setState(() => _loginLoading = true);
    try {
      final logs = await _logService.getLoginHistory(1, 50);
      if (mounted) setState(() => _loginLogs = logs);
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          // Tab栏（紧凑模式）
          Material(
            color: Theme.of(context).primaryColor,
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.sshHistory),
                Tab(text: l10n.loginHistory),
              ],
            ),
          ),
          // 内容区
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLogList(_sshLogs, _sshLoading, 'ssh'),
                _buildLogList(_loginLogs, _loginLoading, 'login'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<dynamic> logs, bool loading, String type) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (logs.isEmpty) return const Center(child: Text('No logs found'));

    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        if (type == 'ssh') {
          return ListTile(
            leading: _getStatusIcon(log['status']),
            title: Text('${log['username']} @ ${log['host']}'),
            subtitle: Text(log['connected_at'] ?? ''),
            trailing: Text(
              log['duration'] != null ? '${log['duration']}s' : '-',
            ),
          );
        } else {
          return ListTile(
            leading: const Icon(Icons.login),
            title: Text(log['ip_address'] ?? 'Unknown IP'),
            subtitle: Text(log['login_at'] ?? ''),
            trailing: Text(log['status'] ?? ''),
          );
        }
      },
    );
  }

  Widget _getStatusIcon(String? status) {
    if (status == 'success')
      return const Icon(Icons.check_circle, color: Colors.green);
    if (status == 'failed') return const Icon(Icons.error, color: Colors.red);
    return const Icon(Icons.info, color: Colors.grey);
  }
}
