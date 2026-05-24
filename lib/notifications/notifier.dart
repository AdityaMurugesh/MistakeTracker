// Owner: Reach & Data
// Glue between SignalSources and flutter_local_notifications.

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';

import 'signal_source.dart';

class LocalNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Map<SignalSource, StreamSubscription> _subscriptions = {};
  final Map<SignalSource, Set<String>> _scheduledTags = {};

  bool _initialized = false;
  bool _permissionsGranted = true; // assume granted; platforms vary

  static const MethodChannel _platform = MethodChannel('mistake_tracker/notifications');

  Future<void> init() async {
    if (_initialized) return;
    try {
      // init timezone data for zoned scheduling
      tz.initializeTimeZones();

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      final initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);

      // Configure Android channel
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final channel = AndroidNotificationChannel(
        'default',
        'Default',
        description: 'General notifications',
        importance: Importance.high,
      );
      try {
        await androidImpl?.createNotificationChannel(channel);
      } catch (_) {}

      // Request runtime notification permission on Android 13+
      // Note: runtime request for POST_NOTIFICATIONS was removed to avoid
      // depending on permission_handler plugin which may be incompatible
      // with this project's environment. If needed, users can grant the
      // permission via system settings. Assume permitted for older platforms.
      _permissionsGranted = true;
    } catch (e) {
      _permissionsGranted = false;
    } finally {
      _initialized = true;
    }
  }

  /// Returns whether notifications are permitted by the OS. This queries the
  /// platform channel (Android) and falls back to the cached value.
  Future<bool> permissionsGranted() async {
    try {
      final bool? granted = await _platform.invokeMethod<bool>('checkNotificationPermission');
      if (granted != null) {
        _permissionsGranted = granted;
        return granted;
      }
    } on PlatformException {
      // ignore and fall back
    } catch (_) {}
    return _permissionsGranted;
  }

  /// Register a SignalSource and schedule incoming triggers.
  void register(SignalSource source) {
    if (_subscriptions.containsKey(source)) return;
    try {
      final sub = source.watch().listen((trigger) async {
        try {
          if (!_initialized) await init();
          await _scheduleTrigger(trigger);
          _scheduledTags.putIfAbsent(source, () => {}).add(trigger.tag);
        } catch (_) {}
      }, onError: (_) {});
      _subscriptions[source] = sub;
    } catch (_) {}
  }

  /// Unregister a previously registered source and cancel its scheduled items.
  void unregister(SignalSource source) {
    final sub = _subscriptions.remove(source);
    sub?.cancel();
    final tags = _scheduledTags.remove(source);
    if (tags != null) {
      for (final tag in tags) {
        cancel(tag);
      }
    }
  }

  Future<void> cancel(String tag) async {
    try {
      final id = tag.hashCode & 0x7fffffff;
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> _scheduleTrigger(NotificationTrigger t) async {
    try {
      if (!_initialized) await init();
      if (!_permissionsGranted) return;

      final id = t.tag.hashCode & 0x7fffffff;
      final scheduled = tz.TZDateTime.from(t.fireAt, tz.local);

      final androidDetails = AndroidNotificationDetails(
        'default',
        'Default',
        channelDescription: 'General notifications',
        importance: Importance.high,
        priority: Priority.high,
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.zonedSchedule(
        id,
        t.title,
        t.body,
        scheduled,
        details,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // swallow scheduling errors — don't crash the app
    }
  }

  /// For demo: show an immediate test notification
  Future<void> scheduleTestNotification() async {
    if (!_initialized) await init();
    try {
      final androidDetails = AndroidNotificationDetails('default', 'Default', channelDescription: 'Demo', importance: Importance.max);
      final details = NotificationDetails(android: androidDetails);
      await _plugin.show(0, 'MistakeTracker (test)', 'This is a test notification.', details);
    } catch (e) {
      rethrow;
    }
  }
}
