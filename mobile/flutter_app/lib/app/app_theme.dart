import 'package:flutter/material.dart';
import 'antd_tokens.dart';

class AppTheme {
  static const Color accent = AntdTokens.primary;
  static const Color online = AntdTokens.success;
  static const Color darkBackground = AntdTokens.darkPage;
  static const Color darkSurface = AntdTokens.darkContainer;
  static const Color darkBorder = AntdTokens.darkBorder;
  static const Color lightBackground = AntdTokens.lightPage;
  static const Color lightText = AntdTokens.lightText;
  static const Color mutedText = AntdTokens.lightTextSecondary;
  static const Color lightBorder = AntdTokens.lightBorder;

  static ThemeData get dark {
    return ThemeData.dark(useMaterial3: false).copyWith(
      visualDensity: VisualDensity.compact,
      textTheme: ThemeData.dark().textTheme.copyWith(
            bodyMedium: const TextStyle(fontSize: 12),
            bodySmall: const TextStyle(fontSize: 11),
            titleMedium:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: darkSurface,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: darkBorder, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(AntdTokens.radius)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(AntdTokens.radius)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(36, 32),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AntdTokens.radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(32, 24),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(32, 32)),
          padding: WidgetStatePropertyAll(EdgeInsets.all(4)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      scaffoldBackgroundColor: darkBackground,
      primaryColor: darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: online,
        surface: darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: AntdTokens.headerHeight,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: accent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1),
      drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
        ),
      ),
    );
  }

  static ThemeData get light {
    return ThemeData.light(useMaterial3: false).copyWith(
      visualDensity: VisualDensity.compact,
      textTheme: ThemeData.light().textTheme.copyWith(
            bodyMedium: const TextStyle(fontSize: 12, color: lightText),
            bodySmall: const TextStyle(fontSize: 11, color: mutedText),
            titleMedium: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: lightText),
          ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: lightBorder, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(AntdTokens.radius)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1),
          borderRadius: BorderRadius.all(Radius.circular(AntdTokens.radius)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(36, 32),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AntdTokens.radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(32, 24),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(32, 32)),
          padding: WidgetStatePropertyAll(EdgeInsets.all(4)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      scaffoldBackgroundColor: lightBackground,
      primaryColor: accent,
      colorScheme: const ColorScheme.light(
        primary: accent,
        secondary: online,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: AntdTokens.headerHeight,
        iconTheme: IconThemeData(color: lightText),
        titleTextStyle: TextStyle(
            color: lightText, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: accent,
        unselectedItemColor: mutedText,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1),
      drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AntdTokens.cardRadius),
        ),
      ),
    );
  }
}
