// Owner: Reach & Data
// v1 SignalSource: emits NotificationTriggers from time-of-day patterns in the DB.
//
// Behavior (v1):
//  - Look back 30 days of entries
//  - Find (what, hour_of_day) buckets with >= 3 hits
//  - For each bucket, emit a NotificationTrigger scheduled ~1 hour before the
//    next occurrence of that hour
//  - Re-evaluates whenever EntryDao.watchAll() emits

import 'dart:async';

import 'signal_source.dart';
import '../data/entry_dao.dart';
import '../domain/models/entry.dart';

class TimeSignal implements SignalSource {
  final EntryDao dao;
  static const Duration _lookback = Duration(days: 30);

  TimeSignal(this.dao);

  @override
  Stream<NotificationTrigger> watch() {
    final controller = StreamController<NotificationTrigger>.broadcast();
    StreamSubscription<List<Entry>>? sub;

    Future<void> _computeAndEmit(List<Entry> entries) async {
      try {
        final nowUtc = DateTime.now().toUtc();
        final sinceUtc = nowUtc.subtract(_lookback);

        // Filter recent entries and group by "what" + hour (local hour)
        final recent = entries.where((e) => e.occurredAt.toUtc().isAfter(sinceUtc)).toList();
        if (recent.isEmpty) return;

        final Map<String, Map<int, List<Entry>>> buckets = {};
        for (final e in recent) {
          final what = (e.what).trim().toLowerCase();
          final hour = e.occurredAt.toLocal().hour;
          buckets.putIfAbsent(what, () => {});
          buckets[what]!.putIfAbsent(hour, () => []).add(e);
        }

        for (final what in buckets.keys) {
          final hourMap = buckets[what]!;
          for (final hour in hourMap.keys) {
            final hits = hourMap[hour]!;
            if (hits.length >= 3) {
              // Compute next occurrence of this hour in local time
              final nowLocal = DateTime.now();
              DateTime next = DateTime(nowLocal.year, nowLocal.month, nowLocal.day, hour);
              if (!next.isAfter(nowLocal)) next = next.add(const Duration(days: 1));

              // Schedule roughly 1 hour before the at-risk window
              DateTime scheduled = next.subtract(const Duration(hours: 1));
              if (!scheduled.isAfter(DateTime.now())) {
                // If the computed time is already past, schedule a short reminder instead
                scheduled = DateTime.now().add(const Duration(minutes: 5));
              }

              final tag = 'time_signal:${what.replaceAll(RegExp(r"\s+"), '_')}:h$hour';
              final title = 'Heads up — recurring "$what"';
              final body = 'You frequently log "$what" around ${hour.toString().padLeft(2, '0')}:00.';

              final trigger = NotificationTrigger(
                title: title,
                body: body,
                fireAt: scheduled,
                tag: tag,
              );

              // Emit trigger (listeners decide whether to schedule)
              controller.add(trigger);
            }
          }
        }
      } catch (e) {
        // Swallow errors to keep stream safe for the app
      }
    }

    // Subscribe to the DAO's watch stream if available
    try {
      sub = dao.watchAll().listen((entries) => _computeAndEmit(entries), onError: (_) {});
    } catch (e) {
      // If DAO isn't implemented yet, ignore; we'll still try a one-shot fetch below
    }

    // Run a one-shot initial fetch (best-effort)
    () async {
      try {
        final since = DateTime.now().toUtc().subtract(_lookback);
        final entries = await dao.getAll(since: since);
        await _computeAndEmit(entries);
      } catch (e) {
        // ignore
      }
    }();

    controller.onCancel = () {
      sub?.cancel();
    };

    return controller.stream;
  }
}
