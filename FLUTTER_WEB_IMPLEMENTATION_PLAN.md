# TermiScope Flutter Web 版实现计划

## 项目概述
将TermiScope的Web前端功能完整迁移到Flutter Web版本，保持与现有Vue前端相同的功能集。

## 功能需求分析

### 1. 认证模块
- 登录/登出功能
- 用户注册/初始化
- 2FA双因素认证
- 密码找回/重置
- 会话管理

### 2. 主机管理模块
- 添加/编辑/删除SSH主机
- 测试SSH连接
- 主机列表展示
- 主机排序功能
- 凭据安全存储

### 3. Web终端模块
- 基于xterm.dart的终端模拟器
- 多标签页支持
- 终端主题定制
- 会话录制功能
- 键盘快捷键支持

### 4. 文件传输模块 (SFTP)
- SFTP文件浏览器
- 文件/文件夹上传下载
- 文件操作（复制、移动、删除、重命名）
- 拖拽上传支持
- 文件预览功能

### 5. 监控模块
- 服务器资源监控（CPU、内存、磁盘、网络IO）
- 网络延迟监控（ICMP/TCP ping）
- 实时图表展示
- 历史数据查询
- 流量统计和限制

### 6. 用户管理模块 (管理员)
- 用户列表管理
- 用户创建/编辑/删除
- 角色权限管理
- 登录历史查看

### 7. 命令管理模块
- 命令模板管理
- 批量命令执行
- 命令历史记录

### 8. 会话记录模块
- 终端会话录制
- 录制文件播放
- 录制文件管理

### 9. 系统管理模块 (管理员)
- 系统配置
- 邮件通知设置
- Telegram通知设置
- 数据备份/恢复
- 系统更新检查

### 10. 连接历史模块
- SSH连接历史
- 会话记录
- 登录历史

### 11. 国际化 (i18n)
- 中英文切换
- 本地化文本

### 12. 主题管理
- 深色/浅色主题
- 自定义主题颜色
- 主题持久化

## 技术架构设计

### 项目结构
```
lib/
├── core/
│   ├── constants.dart          # 应用常量
│   ├── api_client.dart         # API客户端
│   ├── validators.dart         # 表单验证
│   └── utils.dart             # 工具函数
├── models/                    # 数据模型
│   ├── user.dart
│   ├── ssh_host.dart
│   ├── monitor_data.dart
│   ├── network_task.dart
│   ├── recording.dart
│   └── system_config.dart
├── providers/                 # 状态管理
│   ├── auth_provider.dart
│   ├── host_provider.dart
│   ├── monitor_provider.dart
│   ├── terminal_provider.dart
│   ├── sftp_provider.dart
│   ├── user_provider.dart
│   ├── command_provider.dart
│   ├── recording_provider.dart
│   └── system_provider.dart
├── services/                  # 业务服务
│   ├── auth_service.dart
│   ├── host_service.dart
│   ├── monitor_service.dart
│   ├── sftp_service.dart
│   ├── terminal_service.dart
│   ├── user_service.dart
│   ├── command_service.dart
│   ├── recording_service.dart
│   └── system_service.dart
├── ui/
│   ├── screens/               # 页面
│   │   ├── login_screen.dart
│   │   ├── setup_screen.dart
│   │   ├── dashboard_screen.dart
│   │   ├── host_management_screen.dart
│   │   ├── terminal_screen.dart
│   │   ├── sftp_screen.dart
│   │   ├── monitor_dashboard_screen.dart
│   │   ├── user_management_screen.dart
│   │   ├── command_management_screen.dart
│   │   ├── recording_management_screen.dart
│   │   ├── system_management_screen.dart
│   │   ├── connection_history_screen.dart
│   │   ├── profile_screen.dart
│   │   └── forgot_password_screen.dart
│   ├── widgets/               # 可复用组件
│   │   ├── app_drawer.dart
│   │   ├── terminal_widget.dart
│   │   ├── sftp_browser.dart
│   │   ├── monitor_chart.dart
│   │   ├── responsive_container.dart
│   │   ├── loading_indicator.dart
│   │   └── error_message.dart
│   └── themes/                # 主题
│       ├── app_theme.dart
│       └── theme_provider.dart
├── l10n/                      # 国际化
│   ├── app_en.arb
│   └── app_zh.arb
└── main.dart
```

### 依赖配置 (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  provider: ^6.1.5
  dio: ^5.9.1
  shared_preferences: ^2.5.4
  crypto: ^3.0.7
  dartssh2: ^2.13.0
  xterm: ^4.0.0
  web_socket_channel: ^3.0.3
  fl_chart: ^0.68.0
  file_picker: ^8.0.0
  path: ^1.9.0
  intl: ^0.19.0
  url_launcher: ^6.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

## 核心功能实现细节

### 1. API客户端实现
```dart
class ApiClient {
  final Dio _dio = Dio();
  
  ApiClient() {
    _dio.options.baseUrl = 'http://localhost:3000/api'; // 从配置获取
    
    // 请求拦截器 - 添加认证头
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getStoredToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      
      // 响应拦截器 - 处理错误和token刷新
      onResponse: (response, handler) {
        return handler.next(response);
      },
      
      onError: (DioException error, handler) async {
        if (error.response?.statusCode == 401) {
          // 尝试刷新token或重定向到登录
          await handleUnauthorized();
        }
        return handler.next(error);
      },
    ));
  }
  
  // 实现所有API调用方法...
}
```

### 2. 认证Provider
```dart
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  
  AuthStatus _status = AuthStatus.unknown;
  String? _token;
  User? _user;
  
  // 实现登录、登出、token管理等功能...
  
  Future<bool> login(String username, String password) async {
    try {
      final token = await _authService.login(username, password);
      await _storeToken(token);
      _token = token;
      _user = await _authService.getCurrentUser();
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }
}
```

### 3. 终端功能实现
```dart
class TerminalProvider extends ChangeNotifier {
  final Map<String, TerminalSession> _sessions = {};
  String? _activeSessionId;
  
  TerminalSession? get activeSession => 
      _activeSessionId != null ? _sessions[_activeSessionId!] : null;
  
  // 创建SSH连接、终端会话管理、录制功能等
}

class TerminalWidget extends StatefulWidget {
  final TerminalSession session;
  
  const TerminalWidget({Key? key, required this.session}) : super(key: key);
  
  @override
  _TerminalWidgetState createState() => _TerminalWidgetState();
}
```

### 4. SFTP功能实现
```dart
class SftpProvider extends ChangeNotifier {
  final SftpService _sftpService;
  DirectoryContent? _currentDirectory;
  
  // 实现SFTP浏览、上传、下载等功能
  Future<DirectoryContent> browseDirectory(String hostId, String path) async {
    final content = await _sftpService.listDirectory(hostId, path);
    _currentDirectory = content;
    notifyListeners();
    return content;
  }
}

class SftpBrowserWidget extends StatelessWidget {
  // 实现文件浏览器UI
}
```

### 5. 监控功能实现
```dart
class MonitorProvider extends ChangeNotifier {
  final MonitorService _monitorService;
  Map<String, MonitorData> _monitorData = {};
  
  // 实现监控数据获取、WebSocket连接、图表更新等功能
  Stream<MonitorData> subscribeToMonitorUpdates(String hostId) {
    return _monitorService.subscribeToHostUpdates(hostId);
  }
}
```

## 路由和导航
使用Go Router实现页面路由：

```dart
final GoRouter _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      redirect: (context, state) => '/dashboard/terminal',
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
      routes: [
        GoRoute(
          path: 'terminal',
          name: 'terminal',
          builder: (context, state) => const TerminalScreen(),
        ),
        GoRoute(
          path: 'hosts',
          name: 'hosts',
          builder: (context, state) => const HostManagementScreen(),
        ),
        // 其他路由...
      ],
    ),
  ],
  redirectListeners: [
    // 认证检查中间件
  ],
);
```

## 响应式设计
实现桌面端和移动端的不同UI布局：

```dart
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileView;
  final Widget desktopView;
  
  const ResponsiveLayout({
    Key? key,
    required this.mobileView,
    required this.desktopView,
  }) : super(key: key);
  
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 768;
  }
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 768) {
          return mobileView;
        } else {
          return desktopView;
        }
      },
    );
  }
}
```

## 国际化实现
```dart
class AppLocalizations {
  static const LocalizationsDelegate<AppLocalizations> delegate = 
      _AppLocalizationsDelegate();
  
  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }
  
  late final Map<String, String> _localizedStrings;
  
  Future<bool> load(Locale locale) async {
    String jsonString = await rootBundle
        .loadString('lib/l10n/app_${locale.languageCode}.arb');
    Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = jsonMap.map((key, value) => 
        MapEntry(key, value.toString()));
    return true;
  }
  
  String get(String key) => _localizedStrings[key] ?? '';
}
```

## 主题管理
```dart
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light 
        ? ThemeMode.dark 
        : ThemeMode.light;
    notifyListeners();
    _saveThemePreference();
  }
  
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
  );
  
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
  );
}
```

## 开发步骤

### 第一阶段：基础架构搭建
1. 创建Flutter项目并配置依赖
2. 设置项目基本结构
3. 实现API客户端和服务层
4. 实现认证Provider和相关页面

### 第二阶段：核心功能开发
1. 实现主机管理功能
2. 实现终端功能（包括SSH连接和xterm集成）
3. 实现监控功能
4. 实现文件传输功能

### 第三阶段：高级功能开发
1. 实现用户管理功能
2. 实现命令管理功能
3. 实现会话记录功能
4. 实现系统管理功能

### 第四阶段：增强功能
1. 实现国际化功能
2. 实现主题管理功能
3. 实现响应式设计
4. 性能优化和测试

### 第五阶段：部署和发布
1. 构建Web版本
2. 构建桌面版本（Windows, macOS, Linux）
3. 发布和部署文档

## 注意事项
1. 安全性：确保所有API调用都经过适当的身份验证和授权
2. 性能：优化大文件上传下载和终端渲染性能
3. 兼容性：确保在各种浏览器和设备上的兼容性
4. 用户体验：保持与原Vue前端相似的用户体验

## 部署方案
1. Web版本：构建为静态文件部署到Web服务器
2. 桌面版本：打包为独立应用程序
3. 与现有Go后端API无缝集成