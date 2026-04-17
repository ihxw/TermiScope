import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.init();
  
  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const TermiScopeApp(),
    ),
  );
}

class TermiScopeApp extends StatelessWidget {
  const TermiScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Termius-like Dark Theme
    final darkTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF1E1E1E), // Dark background
      primaryColor: const Color(0xFF2D2D2D), // Slightly lighter for appbar/cards
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF64D2FF), // Termius-like blue accent
        secondary: Color(0xFF32D74B), // Green for online status
        surface: Color(0xFF2D2D2D), // Card backgrounds
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2D2D2D),
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF2D2D2D),
        selectedItemColor: Color(0xFF64D2FF),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF2D2D2D),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    return MaterialApp(
      title: 'TermiScope',
      debugShowCheckedModeBanner: false,
      theme: darkTheme, // Force dark theme for sleek look
      home: Consumer<AppState>(
        builder: (context, state, child) {
          if (!state.isInitialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.apiService.token == null || state.apiService.token!.isEmpty) {
            return const LoginScreen();
          }
          return const HomeScreen();
        },
      ),
    );
  }
}
