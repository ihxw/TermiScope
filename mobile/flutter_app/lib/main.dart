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
      visualDensity: VisualDensity.compact,
      // smaller default text sizes for compact mode
      textTheme: ThemeData.dark().textTheme.copyWith(
        bodyMedium: const TextStyle(fontSize: 12),
        bodySmall: const TextStyle(fontSize: 11),
        titleMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: const InputDecorationTheme(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), textStyle: const TextStyle(fontSize: 12)),
      ),
      scaffoldBackgroundColor: const Color(0xFF0D0F18), // Dark background
      primaryColor: const Color(0xFF171B2D), // Slightly lighter for appbar/cards
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFF5C35), // Termius-like orange accent
        secondary: Color(0xFF2ED573), // Green for online status
        surface: Color(0xFF171B2D), // Card backgrounds
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF171B2D),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 44,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF171B2D),
        selectedItemColor: Color(0xFFFF5C35),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF171B2D),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF2D3354), width: 1),
        ),
      ),
    );

    // Premium Termius-like Light Theme
    final lightTheme = ThemeData.light().copyWith(
      visualDensity: VisualDensity.compact,
      textTheme: ThemeData.light().textTheme.copyWith(
        bodyMedium: const TextStyle(fontSize: 12, color: Color(0xFF24292F)),
        bodySmall: const TextStyle(fontSize: 11, color: Color(0xFF57606A)),
        titleMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF24292F)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE1E4E8), width: 1),
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF5C35), width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF5C35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F8FA), // Elegant light grey background
      primaryColor: const Color(0xFFFF5C35),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFFF5C35), // Termius coral-orange accent
        secondary: Color(0xFF2ED573), // Green for online status
        surface: Color(0xFFFFFFFF), // Pristine white card background
        background: const Color(0xFFF6F8FA),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFFFFFF),
        foregroundColor: Color(0xFF24292F),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 44,
        iconTheme: IconThemeData(color: Color(0xFF24292F)),
        titleTextStyle: TextStyle(color: Color(0xFF24292F), fontSize: 16, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        selectedItemColor: Color(0xFFFF5C35),
        unselectedItemColor: Color(0xFF57606A),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardTheme(
        color: const Color(0xFFFFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE1E4E8), width: 1),
        ),
      ),
    );

    return Consumer<AppState>(
      builder: (context, state, child) {
        return MaterialApp(
          title: 'TermiScope',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: state.themeMode,
          home: state.isInitialized == false
              ? const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                )
              : (state.apiService.token == null || state.apiService.token!.isEmpty
                  ? const LoginScreen()
                  : const HomeScreen()),
        );
      },
    );
  }
}
