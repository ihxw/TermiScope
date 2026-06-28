import 'package:flutter/material.dart';

class Responsive {
  // Match web/src/style.css mobile breakpoints.
  static const double desktopBreakpoint = 1000.0;
  static const double tabletBreakpoint = 768.0;
  static const double smallMobileBreakpoint = 480.0;

  static int crossAxisCountFromWidth(double width) {
    if (width >= desktopBreakpoint) return 3;
    if (width >= tabletBreakpoint) return 2;
    return 1;
  }

  static int crossAxisCount(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return crossAxisCountFromWidth(w);
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint &&
      MediaQuery.of(context).size.width < desktopBreakpoint;
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < tabletBreakpoint;
  static bool isSmallMobile(BuildContext context) =>
      MediaQuery.of(context).size.width <= smallMobileBreakpoint;
}
