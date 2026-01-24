import 'package:flutter/material.dart';
import '../../../core/models/ssh_host.dart';
import '../../../shared/theme/app_theme.dart';

/// 主机监控卡片
class HostCard extends StatelessWidget {
  final SshHost host;
  final VoidCallback? onTap;

  const HostCard({
    super.key,
    required this.host,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final monitor = host.monitorData;
    final isOnline = host.monitorStatus == 'online' || monitor != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：主机名和状态
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? AppTheme.successColor : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      host.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${host.host}:${host.port}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 监控数据
              if (monitor != null) ...[
                // CPU 和内存
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.memory,
                        label: 'CPU',
                        value: '${monitor.cpuUsage.toStringAsFixed(1)}%',
                        progress: monitor.cpuUsage / 100,
                        color: _getProgressColor(monitor.cpuUsage),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.storage,
                        label: '内存',
                        value: '${monitor.memoryUsage.toStringAsFixed(1)}%',
                        progress: monitor.memoryUsage / 100,
                        color: _getProgressColor(monitor.memoryUsage),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 磁盘和网络
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.disc_full,
                        label: '磁盘',
                        value: '${monitor.diskUsage.toStringAsFixed(1)}%',
                        progress: monitor.diskUsage / 100,
                        color: _getProgressColor(monitor.diskUsage),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildNetworkItem(
                        rx: monitor.networkRx,
                        tx: monitor.networkTx,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 运行时间
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      '运行时间: ${monitor.formattedUptime}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // 离线或未部署监控
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isOnline ? Icons.sync_disabled : Icons.cloud_off,
                        size: 20,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        host.monitorEnabled ? '等待数据...' : '未部署监控',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required double progress,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.grey.shade700,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkItem({required double rx, required double tx}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.swap_vert, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              '网络',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.arrow_downward,
                size: 12, color: AppTheme.successColor),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                _formatSpeed(rx),
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_upward,
                size: 12, color: AppTheme.primaryColor),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                _formatSpeed(tx),
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getProgressColor(double value) {
    if (value >= 90) return AppTheme.errorColor;
    if (value >= 70) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
    } else if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
  }
}
