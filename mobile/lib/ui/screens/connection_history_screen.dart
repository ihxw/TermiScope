import 'package:flutter/material.dart';
import 'package:mobile/l10n/app_localizations.dart';

class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key});

  @override
  State<ConnectionHistoryScreen> createState() => _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.connectionHistory),
      ),
      body: Center(
        child: Text(l10n.connectionHistoryComingSoon),
      ),
    );
  }
}