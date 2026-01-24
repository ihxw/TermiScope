import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/monitor/pages/monitor_page.dart';
import '../../features/hosts/pages/hosts_page.dart';
import '../../features/hosts/pages/host_edit_page.dart';
import '../../features/network/pages/network_detail_page.dart';

import '../../features/history/pages/history_page.dart';
import '../../features/user/pages/user_list_page.dart';
import '../../features/user/pages/user_edit_page.dart';
import '../models/user.dart';
import '../../features/system/pages/system_settings_page.dart';
import '../../features/system/pages/network_templates_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/terminal/pages/terminal_page.dart';
import '../providers/auth_provider.dart';
import 'shell_page.dart';

/// 认证状态变化通知器
class AuthNotifierForRouter extends ChangeNotifier {
  final Ref ref;
  bool _isAuthenticated = false;

  AuthNotifierForRouter(this.ref) {
    // 初始化状态
    _isAuthenticated = ref.read(authStateProvider).isAuthenticated;
    debugPrint(
        '[AuthNotifierForRouter] Initial state: isAuthenticated=$_isAuthenticated');

    // 监听状态变化
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated) {
        debugPrint(
            '[AuthNotifierForRouter] State changed: ${previous?.isAuthenticated} -> ${next.isAuthenticated}');
        _isAuthenticated = next.isAuthenticated;
        notifyListeners();
      }
    });
  }

  bool get isAuthenticated => _isAuthenticated;
}

final authNotifierForRouterProvider = Provider<AuthNotifierForRouter>((ref) {
  return AuthNotifierForRouter(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authNotifierForRouterProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: authNotifier,
    debugLogDiagnostics: true, // 开启调试日志
    redirect: (context, state) {
      final isAuthenticated = authNotifier.isAuthenticated;
      final location = state.matchedLocation;
      final isLoginRoute = location == '/login';

      debugPrint(
          '[GoRouter] Redirect check: auth=$isAuthenticated, location=$location');

      // 未登录且不在登录页 -> 跳转登录
      if (!isAuthenticated && !isLoginRoute) {
        debugPrint('[GoRouter] Not authenticated, redirecting to /login');
        return '/login';
      }

      // 已登录且在登录页 -> 跳转监控页
      if (isAuthenticated && isLoginRoute) {
        // 检查是否有重定向目标
        final target = state.uri.queryParameters['redirect'];
        if (target != null) {
          debugPrint(
              '[GoRouter] Authenticated, redirecting to target: $target');
          return target;
        }
        debugPrint('[GoRouter] Authenticated, redirecting to /monitor');
        return '/monitor';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => ShellPage(child: child),
        routes: [
          GoRoute(
            path: '/monitor',
            name: 'monitor',
            builder: (context, state) => const MonitorPage(),
          ),
          GoRoute(
            path: '/hosts',
            name: 'hosts',
            builder: (context, state) => const HostsPage(),
            routes: [
              GoRoute(
                path: 'new',
                name: 'host-new',
                builder: (context, state) => const HostEditPage(),
              ),
              GoRoute(
                path: ':id/edit',
                name: 'host-edit',
                builder: (context, state) {
                  final id = int.parse(state.pathParameters['id']!);
                  return HostEditPage(hostId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/monitor/:id/network',
            name: 'network-detail',
            builder: (context, state) {
              final id = int.parse(state.pathParameters['id']!);
              return NetworkDetailPage(hostId: id);
            },
          ),
          GoRoute(
            path: '/history',
            name: 'history',
            builder: (context, state) => const HistoryPage(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/users',
            name: 'users',
            builder: (context, state) => const UserListPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const UserEditPage(),
              ),
              GoRoute(
                path: 'edit/:id',
                builder: (context, state) {
                  // Pass user object via extra if available, otherwise fetch by ID (todo)
                  // For now assuming extra is passed.
                  final user = state.extra as User?;
                  return UserEditPage(user: user);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/system/settings',
            builder: (context, state) => const SystemSettingsPage(),
          ),
          GoRoute(
            path: '/system/templates',
            builder: (context, state) => const NetworkTemplatesPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/terminal/:id',
        name: 'terminal',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return SshTerminalPage(hostId: id);
        },
      ),
    ],
  );
});
