import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _lightTheme = 'light';
  static const String _darkTheme = 'dark';
  static const String _systemTheme = 'system';

  ThemeMode _themeMode = ThemeMode.system;
  Brightness? _brightnessOverride;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get themeMode => _themeMode;
  Brightness get brightness => _brightnessOverride ?? WidgetsBinding.instance.window.platformBrightness;

  /// 切换到浅色主题
  void setLightTheme() {
    _themeMode = ThemeMode.light;
    _brightnessOverride = Brightness.light;
    _saveTheme(_lightTheme);
    notifyListeners();
  }

  /// 切换到深色主题
  void setDarkTheme() {
    _themeMode = ThemeMode.dark;
    _brightnessOverride = Brightness.dark;
    _saveTheme(_darkTheme);
    notifyListeners();
  }

  /// 设置为系统默认主题
  void setSystemTheme() {
    _themeMode = ThemeMode.system;
    _brightnessOverride = null;
    _saveTheme(_systemTheme);
    notifyListeners();
  }

  /// 切换主题模式
  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setDarkTheme();
    } else if (_themeMode == ThemeMode.dark) {
      setSystemTheme();
    } else {
      setLightTheme();
    }
  }

  /// 加载保存的主题设置
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final theme = prefs.getString(_themeKey) ?? _systemTheme;

      switch (theme) {
        case _lightTheme:
          _themeMode = ThemeMode.light;
          _brightnessOverride = Brightness.light;
          break;
        case _darkTheme:
          _themeMode = ThemeMode.dark;
          _brightnessOverride = Brightness.dark;
          break;
        case _systemTheme:
        default:
          _themeMode = ThemeMode.system;
          _brightnessOverride = null;
          break;
      }
    } catch (e) {
      // 如果加载失败，默认使用系统主题
      _themeMode = ThemeMode.system;
      _brightnessOverride = null;
    }
    notifyListeners();
  }

  /// 保存主题设置
  Future<void> _saveTheme(String theme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, theme);
    } catch (e) {
      // 忽略保存错误
    }
  }
}