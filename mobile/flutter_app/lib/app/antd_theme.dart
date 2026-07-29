import 'package:flutter/material.dart';

import 'antd_tokens.dart';

/// AntdTheme 把 [AntdTokens] 组装成可注入到 Widget 树的主题对象。
///
/// 设计上避免直接覆盖 Flutter Material ThemeData，转而提供一个
/// [InheritedWidget]，由各 Antd* 组件按需读取 token，保证视觉与
/// Web 端 ant-design-vue 默认主题一致。
class AntdTheme extends InheritedWidget {
  const AntdTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final AntdThemeData data;

  static AntdThemeData of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<AntdTheme>();
    if (widget != null) return widget.data;
    return AntdThemeData.fromContext(context);
  }

  @override
  bool updateShouldNotify(AntdTheme oldWidget) => data != oldWidget.data;
}

class AntdThemeData {
  AntdThemeData({
    required this.brightness,
    required this.colorPrimary,
    required this.colorSuccess,
    required this.colorWarning,
    required this.colorError,
    required this.colorText,
    required this.colorTextSecondary,
    required this.colorTextDisabled,
    required this.colorBgLayout,
    required this.colorBgContainer,
    required this.colorBgHover,
    required this.colorBorder,
    required this.colorBorderSecondary,
  });

  final Brightness brightness;

  final Color colorPrimary;
  final Color colorSuccess;
  final Color colorWarning;
  final Color colorError;

  final Color colorText;
  final Color colorTextSecondary;
  final Color colorTextDisabled;

  final Color colorBgLayout;
  final Color colorBgContainer;
  final Color colorBgHover;

  final Color colorBorder;
  final Color colorBorderSecondary;

  bool get isDark => brightness == Brightness.dark;

  factory AntdThemeData.fromContext(BuildContext context) {
    final isDark = AntdTokens.isDark(context);
    return AntdThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorPrimary: AntdTokens.primary,
      colorSuccess: AntdTokens.success,
      colorWarning: AntdTokens.warning,
      colorError: AntdTokens.error,
      colorText: isDark ? AntdTokens.darkText : AntdTokens.lightText,
      colorTextSecondary:
          isDark ? AntdTokens.darkTextSecondary : AntdTokens.lightTextSecondary,
      colorTextDisabled:
          isDark ? AntdTokens.darkTextDisabled : AntdTokens.lightTextDisabled,
      colorBgLayout: isDark ? AntdTokens.darkPage : AntdTokens.lightPage,
      colorBgContainer:
          isDark ? AntdTokens.darkContainer : AntdTokens.lightContainer,
      colorBgHover: isDark ? AntdTokens.darkHover : AntdTokens.lightHover,
      colorBorder: isDark ? AntdTokens.darkBorder : AntdTokens.lightBorder,
      colorBorderSecondary: isDark
          ? AntdTokens.darkBorderSecondary
          : AntdTokens.lightBorderSecondary,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AntdThemeData &&
        other.brightness == brightness &&
        other.colorPrimary == colorPrimary &&
        other.colorBgContainer == colorBgContainer &&
        other.colorBorder == colorBorder &&
        other.colorText == colorText;
  }

  @override
  int get hashCode => Object.hash(
        brightness,
        colorPrimary,
        colorBgContainer,
        colorBorder,
        colorText,
      );
}
