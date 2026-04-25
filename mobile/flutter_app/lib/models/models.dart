/// SSH Host model
class Host {
  final int id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String hostType; // 'ssh' or 'monitor_only'
  final bool monitorEnabled;
  final double? netTrafficLimit;
  final int netResetDay;
  final String netTrafficCounterMode;
  final double netTrafficUsedAdjustment;
  final String? expirationDate;
  final double billingAmount;
  final String? billingPeriod;
  final String currency;
  final int? sortOrder;

  Host({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    this.username = 'root',
    this.hostType = 'ssh',
    this.monitorEnabled = false,
    this.netTrafficLimit,
    this.netResetDay = 0,
    this.netTrafficCounterMode = 'both',
    this.netTrafficUsedAdjustment = 0,
    this.expirationDate,
    this.billingAmount = 0,
    this.billingPeriod,
    this.currency = 'CNY',
    this.sortOrder,
  });

  factory Host.fromJson(Map<String, dynamic> json) => Host(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? 'Unnamed',
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? 'root',
        hostType: json['host_type'] as String? ?? 'ssh',
        monitorEnabled: json['monitor_enabled'] == true,
        netTrafficLimit: (json['net_traffic_limit'] as num?)?.toDouble(),
        netResetDay: json['net_reset_day'] as int? ?? 0,
        netTrafficCounterMode:
            json['net_traffic_counter_mode'] as String? ?? 'both',
        netTrafficUsedAdjustment:
            (json['net_traffic_used_adjustment'] as num?)?.toDouble() ?? 0,
        expirationDate: json['expiration_date'] as String?,
        billingAmount:
            (json['billing_amount'] as num?)?.toDouble() ?? 0,
        billingPeriod: json['billing_period'] as String?,
        currency: json['currency'] as String? ?? 'CNY',
        sortOrder: json['sort_order'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'host_type': hostType,
        'monitor_enabled': monitorEnabled,
        'net_traffic_limit': netTrafficLimit,
        'net_reset_day': netResetDay,
        'net_traffic_counter_mode': netTrafficCounterMode,
        'net_traffic_used_adjustment': netTrafficUsedAdjustment,
        'expiration_date': expirationDate,
        'billing_amount': billingAmount,
        'billing_period': billingPeriod,
        'currency': currency,
        'sort_order': sortOrder,
      };
}

/// Command Template model
class CommandTemplate {
  final int id;
  final String name;
  final String command;
  final String description;

  CommandTemplate({
    required this.id,
    required this.name,
    required this.command,
    this.description = '',
  });

  factory CommandTemplate.fromJson(Map<String, dynamic> json) =>
      CommandTemplate(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        command: json['command'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'description': description,
      };
}

/// Connection Log model
class ConnectionLog {
  final int id;
  final int userId;
  final int? sshHostId;
  final String host;
  final int port;
  final String username;
  final String status; // success, failed, disconnected
  final String? errorMessage;
  final DateTime connectedAt;
  final DateTime? disconnectedAt;
  final int duration;
  final String? sshHostName;

  ConnectionLog({
    required this.id,
    required this.userId,
    this.sshHostId,
    required this.host,
    this.port = 22,
    required this.username,
    required this.status,
    this.errorMessage,
    required this.connectedAt,
    this.disconnectedAt,
    this.duration = 0,
    this.sshHostName,
  });

  factory ConnectionLog.fromJson(Map<String, dynamic> json) {
    String? sshHostName;
    if (json['ssh_host'] != null && json['ssh_host'] is Map) {
      sshHostName = json['ssh_host']['name'] as String?;
    }
    return ConnectionLog(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      sshHostId: json['ssh_host_id'] as int?,
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      errorMessage: json['error_message'] as String?,
      connectedAt: DateTime.parse(json['connected_at'] as String),
      disconnectedAt: json['disconnected_at'] != null
          ? DateTime.parse(json['disconnected_at'] as String)
          : null,
      duration: json['duration'] as int? ?? 0,
      sshHostName: sshHostName,
    );
  }
}

/// User Profile model
class UserProfile {
  final int id;
  final String username;
  final String email;
  final String displayName;
  final String role;
  final bool twoFactorEnabled;

  UserProfile({
    required this.id,
    required this.username,
    this.email = '',
    this.displayName = '',
    this.role = 'user',
    this.twoFactorEnabled = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as int? ?? 0,
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        role: json['role'] as String? ?? 'user',
        twoFactorEnabled: json['two_factor_enabled'] == true,
      );
}

/// Login History entry
class LoginSession {
  final int id;
  final String ipAddress;
  final String userAgent;
  final DateTime loginAt;
  final String status; // Active, Revoked, Expired
  final bool isCurrent;
  final String jti;

  LoginSession({
    required this.id,
    required this.ipAddress,
    required this.userAgent,
    required this.loginAt,
    required this.status,
    this.isCurrent = false,
    required this.jti,
  });

  factory LoginSession.fromJson(Map<String, dynamic> json) => LoginSession(
        id: json['id'] as int? ?? 0,
        ipAddress: json['ip_address'] as String? ?? '',
        userAgent: json['user_agent'] as String? ?? '',
        loginAt: DateTime.parse(json['login_at'] as String),
        status: json['status'] as String? ?? 'Unknown',
        isCurrent: json['is_current'] == true,
        jti: json['jti'] as String? ?? '',
      );
}

/// SFTP File Info model
class SftpFileInfo {
  final String name;
  final int size;
  final bool isDir;
  final DateTime modTime;
  final int mode;

  SftpFileInfo({
    required this.name,
    this.size = 0,
    this.isDir = false,
    required this.modTime,
    this.mode = 0,
  });

  factory SftpFileInfo.fromJson(Map<String, dynamic> json) => SftpFileInfo(
        name: json['name'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        isDir: json['is_dir'] == true,
        modTime: json['mod_time'] != null
            ? DateTime.parse(json['mod_time'] as String)
            : DateTime.now(),
        mode: json['mode'] as int? ?? 0,
      );

  String get formattedSize {
    if (size == 0 && !isDir) return '--';
    if (isDir) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedMode {
    final r = (mode >> 6) & 7;
    final w = (mode >> 3) & 7;
    final x = mode & 7;
    return '$r$w$x';
  }
}
