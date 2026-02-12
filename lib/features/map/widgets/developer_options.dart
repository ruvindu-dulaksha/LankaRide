import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Developer options are disabled in production
/// Use the web admin panel at http://localhost:5001/admin for testing parameters
class DeveloperOptions extends ConsumerWidget {
  final VoidCallback onClose;

  const DeveloperOptions({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-close - testing is done via web admin panel only
    Future.microtask(onClose);
    return const SizedBox.shrink();
  }
}
