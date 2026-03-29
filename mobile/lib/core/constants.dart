class AppConstants {
  static const String appName = 'TermiScope';
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String serverUrlKey = 'server_url';
  static const String themeModeKey = 'theme_mode';

  // Default URL for development (Android Emulator loopback)
  // For real device, needs actual IP.
  static const String defaultServerUrl = 'http://127.0.0.1:3000';
  // API Endpoints (with /api prefix to match backend routes)
  static const String loginEndpoint = '/api/auth/login';
  static const String logoutEndpoint = '/api/auth/logout';
  static const String checkInitEndpoint = '/api/auth/check-init';
  static const String initializeEndpoint = '/api/auth/initialize';
  static const String forgotPasswordEndpoint = '/api/auth/forgot-password';
  static const String resetPasswordEndpoint = '/api/auth/reset-password';
  static const String getCurrentUserEndpoint = '/api/auth/me';
  static const String getWSTicketEndpoint = '/api/auth/ws-ticket';
  static const String verify2FAEndpoint = '/api/auth/2fa/verify';
  static const String setup2FAEndpoint = '/api/auth/2fa/setup';
  static const String verifySetup2FAEndpoint = '/api/auth/2fa/verify-setup';
  static const String disable2FAEndpoint = '/api/auth/2fa/disable';
  static const String regenerateBackupCodesEndpoint = '/api/auth/2fa/backup-codes';
  static const String getLoginHistoryEndpoint = '/api/auth/login-history';
  static const String revokeSessionEndpoint = '/api/auth/sessions/revoke';
  static const String changePasswordEndpoint = '/api/auth/change-password';
  static const String verify2FALoginEndpoint = '/api/auth/verify-2fa-login';
  static const String getTokenInfoEndpoint = '/api/auth/token-info';

  // SSH Host Endpoints
  static const String sshHostsEndpoint = '/api/ssh-hosts';
  static const String testConnectionEndpoint = '/api/ssh-hosts/%id%/test';
  static const String updateFingerprintEndpoint = '/api/ssh-hosts/%id%/fingerprint';
  static const String reorderHostsEndpoint = '/api/ssh-hosts/reorder';

  // Monitor Endpoints
  static const String monitorStreamEndpoint = '/api/monitor/stream';
  static const String deployMonitorEndpoint = '/api/ssh-hosts/%id%/monitor/deploy';
  static const String stopMonitorEndpoint = '/api/ssh-hosts/%id%/monitor/stop';
  static const String updateAgentEndpoint = '/api/ssh-hosts/%id%/monitor/update';
  static const String getStatusLogsEndpoint = '/api/ssh-hosts/%id%/monitor/logs';
  static const String getTrafficResetLogsEndpoint = '/api/monitor/traffic-reset-logs';
  static const String getTrafficResetDebugEndpoint = '/api/monitor/traffic-reset-debug/%id%';
  static const String forceTrafficResetEndpoint = '/api/monitor/traffic-reset-force/%id%';

  // Network Monitor Endpoints
  static const String networkTasksEndpoint = '/api/monitor/network/tasks';
  static const String updateNetworkTaskEndpoint = '/api/monitor/network/tasks/%id%';
  static const String deleteNetworkTaskEndpoint = '/api/monitor/network/tasks/%id%';
  static const String getHostNetworkTasksEndpoint = '/api/ssh-hosts/%id%/network/tasks';
  static const String getTaskStatsEndpoint = '/api/monitor/network/stats/%taskId%';
  static const String networkTemplatesEndpoint = '/api/monitor/network/templates';
  static const String updateNetworkTemplateEndpoint = '/api/monitor/network/templates/%id%';
  static const String deleteNetworkTemplateEndpoint = '/api/monitor/network/templates/%id%';
  static const String getTemplateAssignmentsEndpoint = '/api/monitor/network/templates/%id%/assignments';
  static const String batchApplyTemplateEndpoint = '/api/monitor/network/apply-template';

  // SFTP Endpoints
  static const String sftpListEndpoint = '/api/sftp/list/%hostId%';
  static const String sftpDownloadEndpoint = '/api/sftp/download/%hostId%';
  static const String sftpUploadEndpoint = '/api/sftp/upload/%hostId%';
  static const String sftpDeleteEndpoint = '/api/sftp/delete/%hostId%';
  static const String sftpRenameEndpoint = '/api/sftp/rename/%hostId%';
  static const String sftpPasteEndpoint = '/api/sftp/paste/%hostId%';
  static const String sftpMkdirEndpoint = '/api/sftp/mkdir/%hostId%';
  static const String sftpCreateEndpoint = '/api/sftp/create/%hostId%';
  static const String sftpSizeEndpoint = '/api/sftp/size/%hostId%';

  // User Management Endpoints
  static const String usersEndpoint = '/api/users';
  static const String connectionLogsEndpoint = '/api/connection-logs';

  // Command Management Endpoints
  static const String commandTemplatesEndpoint = '/api/command-templates';

  // Recording Management Endpoints
  static const String recordingsEndpoint = '/api/recordings';

  // System Management Endpoints
  static const String systemInfoEndpoint = '/api/system/info';
  static const String checkUpdateEndpoint = '/api/system/check-update';
  static const String upgradeEndpoint = '/api/system/upgrade';
  static const String updateStatusEndpoint = '/api/system/update-status';
  static const String testEmailEndpoint = '/api/system/settings/test-email';
  static const String testTelegramEndpoint = '/api/system/settings/test-telegram';
  static const String systemSettingsEndpoint = '/api/system/settings';
  static const String backupEndpoint = '/api/system/backup';
  static const String restoreEndpoint = '/api/system/restore';

  // Connection Log Endpoints
  static const String getLoginHistoryLogEndpoint = '/api/auth/login-history';
}