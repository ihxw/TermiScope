import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/setup_screen.dart';
import 'app_theme.dart';

class TermiScopeApp extends StatelessWidget {
  const TermiScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return MaterialApp(
          title: 'TermiScope',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: state.themeMode,
          routes: {
            '/login': (_) => const LoginScreen(),
            '/setup': (_) => const SetupScreen(),
            '/forgot-password': (_) => const ForgotPasswordScreen(),
            '/reset-password': (_) => const ResetPasswordScreen(),
            '/dashboard': (_) => const HomeScreen(),
          },
          home: _resolveHome(state),
        );
      },
    );
  }

  Widget _resolveHome(AppState state) {
    if (!state.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final path = Uri.base.path.isEmpty ? '/' : Uri.base.path;
    final token = state.apiService.token;

    if (path == '/forgot-password') {
      return const ForgotPasswordScreen();
    }
    if (path == '/reset-password') {
      return const ResetPasswordScreen();
    }

    if (!state.systemInitialized) {
      return const SetupScreen();
    }

    if (token == null || token.isEmpty) {
      return const LoginScreen();
    }

    return const HomeScreen();
  }
}
