import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile/l10n/app_localizations.dart';

import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/setup_screen.dart';
import 'core/api_client.dart';
import 'providers/auth_provider.dart';
import 'models/user.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/file_transfer_screen.dart';
import 'ui/screens/command_management_screen.dart';
import 'ui/screens/reset_password_screen.dart';
import 'services/auth_service.dart';

// Global instances
final apiClient = ApiClient.instance;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await apiClient.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(AuthService())),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, child) {
          return MaterialApp(
            title: 'TermiScope',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
            ),
            themeMode: themeProvider.themeMode,
            locale: localeProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'), // English
              Locale('zh'), // Chinese
            ],
            initialRoute: '/',
            routes: {
              '/': (context) => const SelectionArea(child: AuthWrapper()),
              '/dashboard': (context) => const MainScreen(),
              '/hosts': (context) => const MainScreen(),
              '/terminal': (context) => const MainScreen(),
              '/transfer': (context) => const FileTransferScreen(),
              '/history': (context) => const MainScreen(),
              '/commands': (context) => const CommandManagementScreen(),
            },
            onGenerateRoute: (settings) {
              if (settings.name?.startsWith('/reset-password') ?? false) {
                final uri = Uri.parse(settings.name!);
                final token = uri.queryParameters['token'] ?? '';
                return MaterialPageRoute(
                  builder: (_) => ResetPasswordScreen(token: token),
                );
              }

              // Handle dynamic routes
              if (settings.name?.startsWith('/dashboard/') ?? false) {
                final pathParts = settings.name!.split('/');
                if (pathParts.length > 2) {
                  final tab = pathParts[2];
                  switch (tab) {
                    case 'terminal':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'hosts':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'monitor':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'users':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'system':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'profile':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'transfer':
                      return MaterialPageRoute(builder: (_) => const FileTransferScreen());
                    case 'history':
                      return MaterialPageRoute(builder: (_) => const MainScreen());
                    case 'commands':
                      return MaterialPageRoute(builder: (_) => const CommandManagementScreen());
                  }
                }
              }
              return MaterialPageRoute(builder: (_) => const MainScreen());
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkInitialization(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isInitialized = snapshot.data ?? false;
        
        return Consumer<AuthProvider>(
          builder: (context, auth, _) {
            // If system is not initialized, show setup screen regardless of auth status
            if (!isInitialized) {
              return const SetupScreen();
            }
            
            switch (auth.status) {
              case AuthStatus.authenticated:
                return const DashboardScreen();
              case AuthStatus.unauthenticated:
                return const LoginScreen();
              case AuthStatus.unknown:
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
            }
          },
        );
      },
    );
  }

  Future<bool> _checkInitialization(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      // Debug: Print API client base URL
      print('DEBUG: API Client base URL: ${ApiClient.instance.baseUrl}');
      print('DEBUG: About to check initialization...');
      
      final result = await authProvider.checkInitialization();
      print('System initialization check result: $result');
      return result;
    } catch (e, stackTrace) {
      // If there's an error checking initialization, show login screen
      // This handles cases where the server is unreachable or API errors
      print('Error checking initialization, showing login screen: $e');
      print('Stack trace: $stackTrace');
      // Return true to skip setup screen and go to login
      return true;
    }
  }
}
