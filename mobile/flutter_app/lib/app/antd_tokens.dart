import 'package:flutter/material.dart';

/// Ant Design 风格设计 Token。
/// 与 Web 端 ant-design-vue 默认主题对齐：
/// 颜色、字号、行高、控件高度、圆角、间距均参考 ant-design 规范。
class AntdTokens {
  // -------- 颜色：主调 --------
  static const Color primary = Color(0xFF1890FF);
  static const Color primaryHover = Color(0xFF40A9FF);
  static const Color primaryActive = Color(0xFF096DD9);
  static const Color success = Color(0xFF52C41A);
  static const Color warning = Color(0xFFFAAD14);
  static const Color error = Color(0xFFFF4D4F);
  static const Color info = primary;

  // -------- 颜色：浅色模式 --------
  static const Color lightPage = Color(0xFFF0F2F5);
  static const Color lightContainer = Color(0xFFFFFFFF);
  static const Color lightContainerSecondary = Color(0xFFFAFAFA);
  static const Color lightText = Color(0xD9000000); // rgba(0,0,0,0.85)
  static const Color lightTextSecondary = Color(0xFF8C8C8C);
  static const Color lightTextDisabled = Color(0x40000000); // rgba(0,0,0,0.25)
  static const Color lightBorder = Color(0xFFD9D9D9);
  static const Color lightBorderSecondary = Color(0xFFF0F0F0);
  static const Color lightHeaderBorder = Color(0xFFF0F0F0);
  static const Color lightHover = Color(0xFFF5F5F5);

  // -------- 颜色：暗色模式 --------
  static const Color darkPage = Color(0xFF141414);
  static const Color darkContainer = Color(0xFF1F1F1F);
  static const Color darkContainerSecondary = Color(0xFF262626);
  static const Color darkText = Color(0xD9FFFFFF); // rgba(255,255,255,0.85)
  static const Color darkTextSecondary = Color(0xFF8C8C8C);
  static const Color darkTextDisabled = Color(0x40FFFFFF);
  static const Color darkBorder = Color(0xFF303030);
  static const Color darkBorderSecondary = Color(0xFF303030);
  static const Color darkHover = Color(0xFF262626);

  // -------- 字号 / 行高 --------
  // Web 端启用了 Ant Design compactAlgorithm。
  static const double fontSizeSM = 11;
  static const double fontSize = 12;
  static const double fontSizeLG = 14;
  static const double fontSizeHeading4 = 20;
  static const double lineHeight = 1.6667;

  // -------- 圆角 --------
  static const double radius = 2;
  static const double radiusLG = 8;
  static const double cardRadius = 8;

  // -------- 控件高度 --------
  static const double controlHeightSM = 24;
  static const double controlHeight = 28;
  static const double controlHeightLG = 36;

  // -------- 间距 --------
  static const double paddingXXS = 2;
  static const double paddingXS = 4;
  static const double paddingSM = 8;
  static const double padding = 12;
  static const double paddingMD = 16;
  static const double paddingLG = 24;

  static const double marginXXS = 2;
  static const double marginXS = 4;
  static const double marginSM = 8;
  static const double margin = 12;
  static const double marginMD = 16;
  static const double marginLG = 24;

  // -------- 页面级常量 --------
  static const double headerHeight = 48;
  static const double mobileBreakpoint = 768;
  static const double smallMobileBreakpoint = 480;
  static const double mobileContentPadding = 8;
  static const double smallMobileContentPadding = 4;
  static const double tableHeaderHeight = 38;
  static const double tableRowHeight = 46;
  static const double cardHeaderHeight = 40;
  static const double modalWidth = 520;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageColor(BuildContext context) =>
      isDark(context) ? darkPage : lightPage;

  static Color containerColor(BuildContext context) =>
      isDark(context) ? darkContainer : lightContainer;

  static Color borderColor(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;

  static Color secondaryTextColor(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;

  static Color textColor(BuildContext context) =>
      isDark(context) ? darkText : lightText;

  static Color disabledTextColor(BuildContext context) =>
      isDark(context) ? darkTextDisabled : lightTextDisabled;

  static Color borderSecondaryColor(BuildContext context) =>
      isDark(context) ? darkBorderSecondary : lightBorderSecondary;

  static Color hoverColor(BuildContext context) =>
      isDark(context) ? darkHover : lightHover;

  static Color containerSecondaryColor(BuildContext context) =>
      isDark(context) ? darkContainerSecondary : lightContainerSecondary;

  static double contentPaddingForWidth(double width) =>
      width <= smallMobileBreakpoint
          ? smallMobileContentPadding
          : width <= mobileBreakpoint
              ? mobileContentPadding
              : width <= 1024
                  ? 12
                  : mobileContentPadding;

  static double headerPaddingForWidth(double width) =>
      width <= smallMobileBreakpoint
          ? 8
          : (width <= mobileBreakpoint ? 12 : 24);

  static double contentPadding(BuildContext context) =>
      contentPaddingForWidth(MediaQuery.of(context).size.width);

  static double cardBodyPaddingForWidth(double width) =>
      width <= smallMobileBreakpoint ? 8 : 12;

  static double cardBodyPadding(BuildContext context) =>
      cardBodyPaddingForWidth(MediaQuery.of(context).size.width);
}
