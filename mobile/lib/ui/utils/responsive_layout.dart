import 'package:flutter/material.dart';

/// 响应式布局工具类
/// 断点参考Web版本: 768px
class ResponsiveLayout {
  /// 移动端断点
  static const double mobileBreakpoint = 768;

  /// 判断是否为移动端布局
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width <= mobileBreakpoint;
  }

  /// 判断是否为PC端布局
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width > mobileBreakpoint;
  }

  /// 获取屏幕宽度
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// 获取屏幕高度
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// 响应式数值选择
  static T value<T>(
    BuildContext context, {
    required T mobile,
    required T desktop,
  }) {
    return isMobile(context) ? mobile : desktop;
  }

  /// 响应式EdgeInsets
  static EdgeInsets padding(
    BuildContext context, {
    EdgeInsets mobile = const EdgeInsets.all(8),
    EdgeInsets desktop = const EdgeInsets.all(16),
  }) {
    return isMobile(context) ? mobile : desktop;
  }
}

/// 响应式构建器Widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool isMobile) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(context, ResponsiveLayout.isMobile(context));
  }
}
