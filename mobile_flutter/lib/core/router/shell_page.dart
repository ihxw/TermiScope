import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 主框架页面，包含底部导航栏
class ShellPage extends StatelessWidget {
  final Widget child;

  const ShellPage({super.key, required this.child});

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/monitor')) return 0;
    if (location.startsWith('/hosts')) return 1;
    if (location.startsWith('/history')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onTabTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/monitor');
        break;
      case 1:
        context.go('/hosts');
        break;
      case 2:
        context.go('/history');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _getCurrentIndex(context),
        onTap: (index) => _onTabTapped(context, index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: '监控',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dns_outlined),
            activeIcon: Icon(Icons.dns),
            label: '主机',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: '历史',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
