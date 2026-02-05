// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'TermiScope';

  @override
  String get monitor => '监控';

  @override
  String get hosts => '主机';

  @override
  String get history => '历史';

  @override
  String get commands => '指令';

  @override
  String get recordings => '录像';

  @override
  String get settings => '设置';

  @override
  String get profile => '个人中心';

  @override
  String get users => '用户管理';

  @override
  String get system => '系统设置';

  @override
  String get logout => '注销';

  @override
  String get login => '登录';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get welcomeBack => '欢迎回来!';

  @override
  String get signInToContinue => '请登录以继续';

  @override
  String get changePassword => '修改密码';

  @override
  String get currentPassword => '当前密码';

  @override
  String get newPassword => '新密码';

  @override
  String get confirmPassword => '确认密码';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';

  @override
  String get passwordChanged => '密码修改成功';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get refresh => '刷新';

  @override
  String get sshConnections => 'SSH连接';

  @override
  String get loginHistory => '登录历史';

  @override
  String get sshTimeout => 'SSH超时';

  @override
  String get idleTimeout => '空闲超时';

  @override
  String get smtpServer => 'SMTP服务器';

  @override
  String get backup => '备份';

  @override
  String get downloadBackup => '下载备份';

  @override
  String get comingSoon => '敬请期待';

  @override
  String get featureNotImplemented => '该功能尚未实现。';

  @override
  String get statusAuthenticated => '已认证';

  @override
  String get statusUnauthenticated => '未认证';

  @override
  String get email => '邮箱';

  @override
  String get role => '角色';

  @override
  String get status => '状态';

  @override
  String get lastLogin => '最后登录';

  @override
  String get add => '添加';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get confirmDelete => '确定要删除吗？';

  @override
  String get error => '错误';

  @override
  String get success => '成功';

  @override
  String get enterServerUrl => '请输入服务器地址';

  @override
  String get addUser => '添加用户';

  @override
  String get editUser => '编辑用户';

  @override
  String get active => '激活';

  @override
  String get disabled => '禁用';

  @override
  String get userRole => '普通用户';

  @override
  String get admin => '管理员';

  @override
  String get accessExpiration => '访问过期时间';

  @override
  String get limits => '限制';

  @override
  String get maxConnectionsPerUser => '最大连接数/用户';

  @override
  String get loginRateLimit => '登录速率限制';

  @override
  String get port => '端口';

  @override
  String get senderEmail => '发送者邮箱';

  @override
  String get adminEmail => '管理员邮箱';

  @override
  String get saveSettings => '保存设置';

  @override
  String get systemBackup => '系统备份';

  @override
  String get enterBackupPassword => '输入密码以加密备份文件:';

  @override
  String get startBackup => '开始备份';

  @override
  String get leaveBlankToKeep => '留空以保持当前密码';

  @override
  String get retry => '重试';

  @override
  String get noHostsFound => '未发现主机';

  @override
  String get noHostsMonitored => '未监控主机';

  @override
  String get cpu => 'CPU';

  @override
  String get ram => '内存';

  @override
  String get disk => '磁盘';

  @override
  String get connect => '连接';

  @override
  String get monitorOffline => '离线';

  @override
  String get connectToTerminal => '连接终端';

  @override
  String get terminal => '终端';

  @override
  String get terminals => '终端管理';

  @override
  String get terminalSelectHost => '选择主机';

  @override
  String get terminalQuickConnect => '快速连接';

  @override
  String get terminalNewHost => '新增主机';

  @override
  String get terminalRecordSession => '录制会话';

  @override
  String get terminalNoActive => '暂无活跃终端';

  @override
  String get terminalConnectToHost => '连接到主机';

  @override
  String get serverHost => '服务器地址';

  @override
  String get monitorTotal => '共';

  @override
  String get monitorOnline => '在线';

  @override
  String get networkTitle => '网络详情';

  @override
  String get monitorOnly => '仅监控';

  @override
  String get monitorHistory => '历史记录';

  @override
  String get uptime => '运行时间';

  @override
  String get agentOutdated => 'Agent过期';

  @override
  String get networkUsage => '流量使用';

  @override
  String get expirationDate => '过期时间';

  @override
  String remainingDays(Object days) {
    return '$days天';
  }

  @override
  String get remainingValueLong => '剩余价值';

  @override
  String get expired => '已过期';

  @override
  String get daysRemaining => '天剩余';

  @override
  String get billingMonthly => '月付';

  @override
  String get billingQuarterly => '季付';

  @override
  String get billingSemiannually => '半年付';

  @override
  String get billingAnnually => '年付';

  @override
  String get billingBiennial => '两年付';

  @override
  String get billingTriennial => '三年付';

  @override
  String get billingOneTime => '一次性';
}
