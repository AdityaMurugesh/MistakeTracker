// Owner: Reach & Data
// Toggles + export button.
//
// TODO:
//   - "Export my data" button -> ExportService.shareLatestExport()
//   - "Notifications" toggle  -> enable/disable Notifier
//   - "Permissions" banner if POST_NOTIFICATIONS denied (Android 13+)
//   - "About" tile linking to GitHub repo

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('TODO: settings tiles')),
    );
  }
}
