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
import 'package:flutter/services.dart';

import '../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(notifierProvider);
    final exportService = ref.watch(exportServiceProvider);
    final timeSignal = ref.watch(timeSignalProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            FutureBuilder<bool>(
              future: notifier.permissionsGranted(),
              builder: (context, snap) {
                final perms = snap.data ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Enable notifications'),
                      value: notificationsEnabled,
                      onChanged: (v) async {
                        if (v) {
                          // Request OS runtime permission for notifications (Android 13+)
                          final channel = MethodChannel('mistake_tracker/notifications');
                          bool granted = false;
                          try {
                            granted = await channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
                          } catch (_) {
                            // platform call failed; treat as not granted
                            granted = false;
                          }

                          if (!granted) {
                            // Do not enable in-app scheduling if OS permission not granted
                            ref.read(notificationsEnabledProvider.notifier).state = false;
                            return;
                          }

                          try {
                            ref.read(notificationsEnabledProvider.notifier).state = true;
                            notifier.register(timeSignal);
                          } catch (_) {
                            ref.read(notificationsEnabledProvider.notifier).state = false;
                          }
                        } else {
                          try {
                            notifier.unregister(timeSignal);
                            ref.read(notificationsEnabledProvider.notifier).state = false;
                          } catch (_) {
                            // ignore errors silently
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Notification permission :'),
                        const SizedBox(width: 8),
                        if (snap.connectionState == ConnectionState.waiting) const CircularProgressIndicator(strokeWidth: 2) else Text(perms ? 'Granted' : 'Denied', style: TextStyle(color: perms ? Colors.green : Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Test notification should depend only on OS-level permission
                        final perms = await notifier.permissionsGranted();
                        if (!perms) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification permission not granted in settings')));
                          return;
                        }

                        try {
                          await notifier.scheduleTestNotification();
                        } catch (_) {
                          // ignore scheduling errors silently
                        }
                      },
                      icon: const Icon(Icons.notifications),
                      label: const Text('Send test notification'),
                    ),
                    const SizedBox(height: 18),
                    const Divider(),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await exportService.shareLatestExport();
                } catch (_) {
                  // ignore export errors silently
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Export my data'),
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('MistakeTracker — local-only demo'),
              onTap: () {},
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
