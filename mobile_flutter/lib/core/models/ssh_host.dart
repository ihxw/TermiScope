/// SSH 主机模型
class SshHost {
  final int id;
  final int userId;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authType;
  final String? groupName;
  final String? tags;
  final String? description;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // 监控相关
  final bool monitorEnabled;
  final String? monitorStatus;
  final MonitorData? monitorData;

  SshHost({
    required this.id,
    required this.userId,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.authType,
    this.groupName,
    this.tags,
    this.description,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
    this.monitorEnabled = false,
    this.monitorStatus,
    this.monitorData,
  });

  factory SshHost.fromJson(Map<String, dynamic> json) {
    return SshHost(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      port: json['port'] ?? 22,
      username: json['username'] ?? '',
      authType: json['auth_type'] ?? 'password',
      groupName: json['group_name'],
      tags: json['tags'],
      description: json['description'],
      sortOrder: json['sort_order'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      monitorEnabled: json['monitor_enabled'] ?? false,
      monitorStatus: json['monitor_status'],
      monitorData: json['monitor_data'] != null
          ? MonitorData.fromJson(json['monitor_data'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'auth_type': authType,
      'group_name': groupName,
      'tags': tags,
      'description': description,
    };
  }

  SshHost copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authType,
    String? groupName,
    String? description,
    MonitorData? monitorData,
  }) {
    return SshHost(
      id: id ?? this.id,
      userId: userId,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      groupName: groupName ?? this.groupName,
      tags: tags,
      description: description ?? this.description,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
      monitorEnabled: monitorEnabled,
      monitorStatus: monitorStatus,
      monitorData: monitorData ?? this.monitorData,
    );
  }
}

/// 监控数据模型
class MonitorData {
  final int? hostId;
  final double cpuUsage;
  final double memoryUsage;
  final double memoryTotal;
  final double memoryUsed;
  final double diskUsage;
  final double diskTotal;
  final double diskUsed;
  final double networkRx;
  final double networkTx;
  final int uptime;
  final DateTime? lastUpdate;

  MonitorData({
    this.hostId,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.memoryTotal = 0,
    this.memoryUsed = 0,
    this.diskUsage = 0,
    this.diskTotal = 0,
    this.diskUsed = 0,
    this.networkRx = 0,
    this.networkTx = 0,
    this.uptime = 0,
    this.lastUpdate,
  });

  factory MonitorData.fromJson(Map<String, dynamic> json) {
    // Calculate percentages
    double memUsage = 0;
    final double memTotal = (json['mem_total'] ?? 0).toDouble();
    final double memUsed = (json['mem_used'] ?? 0).toDouble();
    if (memTotal > 0) {
      memUsage = (memUsed / memTotal) * 100;
    }

    double diskUsage = 0;
    final double diskTotal = (json['disk_total'] ?? 0).toDouble();
    final double diskUsed = (json['disk_used'] ?? 0).toDouble();
    if (diskTotal > 0) {
      diskUsage = (diskUsed / diskTotal) * 100;
    }

    return MonitorData(
      hostId: json['host_id'],
      cpuUsage: (json['cpu'] ?? 0).toDouble(),
      memoryUsage: memUsage,
      memoryTotal: memTotal,
      memoryUsed: memUsed,
      diskUsage: diskUsage,
      diskTotal: diskTotal,
      diskUsed: diskUsed,
      networkRx: (json['net_rx_rate'] ?? 0).toDouble(),
      networkTx: (json['net_tx_rate'] ?? 0).toDouble(),
      uptime: json['uptime'] ?? 0,
      lastUpdate: json['last_updated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['last_updated'] as int) * 1000)
          : null,
    );
  }

  String get formattedUptime {
    final days = uptime ~/ 86400;
    final hours = (uptime % 86400) ~/ 3600;
    final minutes = (uptime % 3600) ~/ 60;

    if (days > 0) {
      return '$days天 $hours小时';
    } else if (hours > 0) {
      return '$hours小时 $minutes分钟';
    } else {
      return '$minutes分钟';
    }
  }
}
