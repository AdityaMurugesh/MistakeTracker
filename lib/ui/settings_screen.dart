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

class _AiInsightsSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AiInsightsSection> createState() => _AiInsightsSectionState();
}

class _AiInsightsSectionState extends ConsumerState<_AiInsightsSection> {
  late final TextEditingController _hostCtl;
  late final TextEditingController _modelCtl;
  bool _bound = false;

  @override
  void initState() {
    super.initState();
    _hostCtl = TextEditingController();
    _modelCtl = TextEditingController();
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _modelCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiSettingsProvider);

    // Seed controllers once when the persisted values arrive.
    if (!_bound) {
      _hostCtl.text = ai.host;
      _modelCtl.text = ai.model;
      _bound = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI insights',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Swap the rule-based engine for a local LLM via Ollama. Falls back to the rule engine on any error.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use AI insights'),
          subtitle: Text('Model: ${ai.model}  •  ${ai.host}',
              style: const TextStyle(fontSize: 12)),
          value: ai.enabled,
          onChanged: (v) =>
              ref.read(aiSettingsProvider.notifier).setEnabled(v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hostCtl,
          decoration: const InputDecoration(
            labelText: 'Ollama host',
            helperText:
                '10.0.2.2 = host machine from Android emulator. Use localhost on iOS sim.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) =>
              ref.read(aiSettingsProvider.notifier).setHost(v.trim()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _modelCtl,
          decoration: const InputDecoration(
            labelText: 'Model',
            helperText: 'e.g. llama3.2, qwen2.5:14b',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) =>
              ref.read(aiSettingsProvider.notifier).setModel(v.trim()),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              ref
                  .read(aiSettingsProvider.notifier)
                  .setHost(_hostCtl.text.trim());
              ref
                  .read(aiSettingsProvider.notifier)
                  .setModel(_modelCtl.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('AI settings saved'),
                duration: Duration(seconds: 1),
              ));
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save host / model'),
          ),
        ),
      ],
    );
  }
}

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
            _AiInsightsSection(),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            const Text('Appearance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Theme'),
              trailing: DropdownButton<ThemeMode>(
                value: ref.watch(themeModeProvider),
                items: const [
                  DropdownMenuItem(value: ThemeMode.light, child: Text('Light mode')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark mode')),
                  DropdownMenuItem(value: ThemeMode.system, child: Text('System settings')),
                ],
                onChanged: (mode) async {
                  if (mode == null) return;
                  await ref.read(themeModeProvider.notifier).setMode(mode);
                },
              ),
            ),
            const SizedBox(height: 18),
            const Divider(),
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
