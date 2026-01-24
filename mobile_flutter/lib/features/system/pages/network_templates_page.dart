import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NetworkTemplatesPage extends ConsumerWidget {
  const NetworkTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Network Templates')),
      body: const Center(
        child: Text('Coming Soon'),
      ),
    );
  }
}
