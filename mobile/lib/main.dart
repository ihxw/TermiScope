import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'data/services/api_service.dart';
import 'data/services/auth_service.dart';
import 'data/services/host_service.dart';
import 'providers/auth_provider.dart';
import 'providers/host_provider.dart';
import 'providers/monitor_provider.dart';
import 'providers/terminal_provider.dart';
import 'data/services/monitor_service.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/host_list_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ProxyProvider<ApiService, AuthService>(
          update: (_, api, __) => AuthService(api),
        ),
        ProxyProvider<ApiService, HostService>(
          update: (_, api, __) => HostService(api),
        ),
        ProxyProvider<ApiService, MonitorService>(
          update: (_, api, __) => MonitorService(api),
        ),
        ChangeNotifierProxyProvider<AuthService, AuthProvider>(
          create: (context) =>
              AuthProvider(Provider.of<AuthService>(context, listen: false)),
          update: (_, authService, authProvider) => AuthProvider(authService),
        ),
        ChangeNotifierProxyProvider<HostService, HostProvider>(
          create: (context) =>
              HostProvider(Provider.of<HostService>(context, listen: false)),
          update: (_, hostService, __) => HostProvider(hostService),
        ),
        ChangeNotifierProxyProvider2<
          MonitorService,
          HostService,
          MonitorProvider
        >(
          create: (context) => MonitorProvider(
            Provider.of<MonitorService>(context, listen: false),
            Provider.of<HostService>(context, listen: false),
          ),
          update: (_, monitorService, hostService, __) =>
              MonitorProvider(monitorService, hostService),
        ),
        ChangeNotifierProvider(create: (_) => TerminalProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
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
        home: const SelectionArea(child: AuthWrapper()),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        switch (auth.status) {
          case AuthStatus.authenticated:
            return const HostListScreen();
          case AuthStatus.unauthenticated:
            return const LoginScreen();
          case AuthStatus.unknown:
          default:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
        }
      },
    );
  }
}
