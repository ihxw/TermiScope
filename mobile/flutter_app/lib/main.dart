import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/termiscope_app.dart';
import 'providers/app_state.dart';

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
