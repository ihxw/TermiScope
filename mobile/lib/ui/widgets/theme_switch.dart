import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../l10n/app_localizations.dart';

class ThemeSwitch extends StatelessWidget {
  const ThemeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return PopupMenuButton<String>(
          icon: Icon(
            themeProvider.themeMode == ThemeMode.light
                ? Icons.light_mode
                : themeProvider.themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.auto_mode,
          ),
          onSelected: (String theme) {
            switch (theme) {
              case 'light':
                themeProvider.setLightTheme();
                break;
              case 'dark':
                themeProvider.setDarkTheme();
                break;
              case 'system':
                themeProvider.setSystemTheme();
                break;
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'light',
              child: Row(
                children: [
                  const Icon(Icons.light_mode),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.lightTheme ?? 'Light Theme'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'dark',
              child: Row(
                children: [
                  const Icon(Icons.dark_mode),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.darkTheme ?? 'Dark Theme'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'system',
              child: Row(
                children: [
                  const Icon(Icons.auto_mode),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.systemTheme ?? 'System Theme'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}