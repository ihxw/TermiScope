/// 系统设置模型
class SystemSettings {
  /// 服务器时区
  final String timezone;
  
  /// SSH超时时间
  final String sshTimeout;
  
  /// 空闲超时时间
  final String idleTimeout;
  
  /// 每个用户的最大连接数
  final int maxConnectionsPerUser;
  
  /// 登录速率限制
  final int loginRateLimit;
  
  /// 访问令牌过期时间
  final String accessExpiration;
  
  /// 刷新令牌过期时间
  final String refreshExpiration;
  
  /// SMTP服务器地址
  final String smtpServer;
  
  /// SMTP端口
  final String smtpPort;
  
  /// SMTP用户名
  final String smtpUser;
  
  /// SMTP密码
  final String smtpPassword;
  
  /// 发件人邮箱
  final String smtpFrom;
  
  /// 收件人邮箱
  final String smtpTo;
  
  /// 是否跳过TLS验证
  final bool smtpSkipVerify;
  
  /// Telegram机器人令牌
  final String telegramBotToken;
  
  /// Telegram聊天ID
  final String telegramChatID;
  
  /// 通知模板
  final String notificationTemplate;

  SystemSettings({
    required this.timezone,
    required this.sshTimeout,
    required this.idleTimeout,
    required this.maxConnectionsPerUser,
    required this.loginRateLimit,
    required this.accessExpiration,
    required this.refreshExpiration,
    required this.smtpServer,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPassword,
    required this.smtpFrom,
    required this.smtpTo,
    required this.smtpSkipVerify,
    required this.telegramBotToken,
    required this.telegramChatID,
    required this.notificationTemplate,
  });

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    return SystemSettings(
      timezone: json['timezone'] ?? '',
      sshTimeout: json['ssh_timeout'] ?? '30s',
      idleTimeout: json['idle_timeout'] ?? '30m',
      maxConnectionsPerUser: json['max_connections_per_user'] ?? 10,
      loginRateLimit: json['login_rate_limit'] ?? 5,
      accessExpiration: json['access_expiration'] ?? '1h',
      refreshExpiration: json['refresh_expiration'] ?? '168h',
      smtpServer: json['smtp_server'] ?? '',
      smtpPort: json['smtp_port'] ?? '',
      smtpUser: json['smtp_user'] ?? '',
      smtpPassword: json['smtp_password'] ?? '',
      smtpFrom: json['smtp_from'] ?? '',
      smtpTo: json['smtp_to'] ?? '',
      smtpSkipVerify: json['smtp_tls_skip_verify'] == true || json['smtp_tls_skip_verify'] == 'true',
      telegramBotToken: json['telegram_bot_token'] ?? '',
      telegramChatID: json['telegram_chat_id'] ?? '',
      notificationTemplate: json['notification_template'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timezone': timezone,
      'ssh_timeout': sshTimeout,
      'idle_timeout': idleTimeout,
      'max_connections_per_user': maxConnectionsPerUser,
      'login_rate_limit': loginRateLimit,
      'access_expiration': accessExpiration,
      'refresh_expiration': refreshExpiration,
      'smtp_server': smtpServer,
      'smtp_port': smtpPort,
      'smtp_user': smtpUser,
      'smtp_password': smtpPassword,
      'smtp_from': smtpFrom,
      'smtp_to': smtpTo,
      'smtp_tls_skip_verify': smtpSkipVerify,
      'telegram_bot_token': telegramBotToken,
      'telegram_chat_id': telegramChatID,
      'notification_template': notificationTemplate,
    };
  }
}

/// 更新系统设置请求模型
class UpdateSettingsRequest {
  final String timezone;
  final String sshTimeout;
  final String idleTimeout;
  final int maxConnectionsPerUser;
  final int loginRateLimit;
  final String accessExpiration;
  final String refreshExpiration;
  final String smtpServer;
  final String smtpPort;
  final String smtpUser;
  final String smtpPassword;
  final String smtpFrom;
  final String smtpTo;
  final bool smtpSkipVerify;
  final String telegramBotToken;
  final String telegramChatID;
  final String notificationTemplate;

  UpdateSettingsRequest({
    required this.timezone,
    required this.sshTimeout,
    required this.idleTimeout,
    required this.maxConnectionsPerUser,
    required this.loginRateLimit,
    required this.accessExpiration,
    required this.refreshExpiration,
    required this.smtpServer,
    required this.smtpPort,
    required this.smtpUser,
    required this.smtpPassword,
    required this.smtpFrom,
    required this.smtpTo,
    required this.smtpSkipVerify,
    required this.telegramBotToken,
    required this.telegramChatID,
    required this.notificationTemplate,
  });

  Map<String, dynamic> toJson() {
    return {
      'timezone': timezone,
      'ssh_timeout': sshTimeout,
      'idle_timeout': idleTimeout,
      'max_connections_per_user': maxConnectionsPerUser,
      'login_rate_limit': loginRateLimit,
      'access_expiration': accessExpiration,
      'refresh_expiration': refreshExpiration,
      'smtp_server': smtpServer,
      'smtp_port': smtpPort,
      'smtp_user': smtpUser,
      'smtp_password': smtpPassword,
      'smtp_from': smtpFrom,
      'smtp_to': smtpTo,
      'smtp_tls_skip_verify': smtpSkipVerify,
      'telegram_bot_token': telegramBotToken,
      'telegram_chat_id': telegramChatID,
      'notification_template': notificationTemplate,
    };
  }
}

/// 更新状态响应模型
class UpdateStatusResponse {
  final String status;
  final String? error;

  UpdateStatusResponse({
    required this.status,
    this.error,
  });

  factory UpdateStatusResponse.fromJson(Map<String, dynamic> json) {
    return UpdateStatusResponse(
      status: json['status'] ?? '',
      error: json['error'],
    );
  }
}

/// 更新检查响应模型
class UpdateCheckResponse {
  final bool updateAvailable;
  final String? version;
  final String? body;
  final String? downloadUrl;
  final String? size;

  UpdateCheckResponse({
    required this.updateAvailable,
    this.version,
    this.body,
    this.downloadUrl,
    this.size,
  });

  factory UpdateCheckResponse.fromJson(Map<String, dynamic> json) {
    return UpdateCheckResponse(
      updateAvailable: json['update_available'] ?? false,
      version: json['version'],
      body: json['body'],
      downloadUrl: json['download_url'],
      size: json['size'],
    );
  }
}