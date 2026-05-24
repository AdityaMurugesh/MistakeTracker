// Owner: Reach & Data (initial setup) — but every role adds their own providers here.
// Riverpod providers: DI container + reactive state.
//
// TODO (Reach & Data Day 1 shared setup):
//   - appDatabaseProvider     -> AppDatabase.instance
//   - entryDaoProvider        -> EntryDao(db)
//   - exportServiceProvider   -> ExportService(dao)
//   - notifierProvider        -> Notifier()
//   - timeSignalProvider      -> TimeSignal(dao)
//
// Reactive providers each role adds:
//   - entriesStreamProvider   (Capture)
//   - suggestionEngineProvider (Insights — below)
//   - insightsProvider        (Insights — below, recomputed when entries change)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/entry.dart';
import '../domain/models/insight.dart';
import '../domain/rule_engine.dart';
import '../domain/suggestion_engine.dart';

// --- Insights providers ---

final suggestionEngineProvider = Provider<SuggestionEngine>((ref) {
  return RuleEngine();
});

/// Temporary entries source so Insights can render REAL engine output before
/// Capture's `entriesStreamProvider` lands. Swap to the real provider in one
/// place when it does.
// TODO(insights): replace with `entriesStreamProvider` once Capture lands it.
final entriesProvider = Provider<List<Entry>>((ref) {
  // Build entries relative to "now" so the lookback window keeps catching them
  // as time moves on.
  DateTime atRecentWeekday(int weekday, int hour, {int weeksAgo = 0}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, hour);
    final delta = (today.weekday - weekday + 7) % 7;
    return today.subtract(Duration(days: delta + 7 * weeksAgo));
  }

  const monday = 1;
  const friday = 5;

  Entry mk({
    required int id,
    required String what,
    String? cause,
    String? solution,
    required DateTime occurredAt,
    int? costMinutes,
    int? costMoney,
  }) {
    return Entry(
      id: id,
      what: what,
      cause: cause,
      solution: solution,
      occurredAt: occurredAt,
      costMinutes: costMinutes,
      costMoney: costMoney,
      createdAt: occurredAt,
    );
  }

  final entries = <Entry>[];

  // Missed workouts: Mondays 7am, last 3 weeks. Triggers recurring-cause
  // ("tired"), weekday pattern (Monday), and hour pattern (7 AM).
  for (var w = 0; w < 3; w++) {
    entries.add(mk(
      id: entries.length + 1,
      what: 'missed workout',
      cause: 'tired',
      occurredAt: atRecentWeekday(monday, 7, weeksAgo: w),
      solution: w == 0 ? 'lay out gear the night before' : null,
    ));
  }

  // Impulse purchases: Fridays 9pm, last 3 weeks. Triggers recurring-cause
  // ("bored"), weekday pattern (Friday), hour pattern (9 PM), and cost.
  const purchaseCosts = [800, 1200, 400];
  for (var w = 0; w < 3; w++) {
    entries.add(mk(
      id: entries.length + 1,
      what: 'impulse purchase',
      cause: 'bored',
      occurredAt: atRecentWeekday(friday, 21, weeksAgo: w),
      costMoney: purchaseCosts[w],
    ));
  }

  // One-off so the cost insight aggregates from more than one `what`.
  entries.add(mk(
    id: entries.length + 1,
    what: 'skipped breakfast',
    occurredAt: DateTime.now().subtract(const Duration(days: 1)),
    costMinutes: 20,
  ));

  return entries;
});

/// Insights for the current set of entries.
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  final entries = ref.watch(entriesProvider);
  final engine = ref.read(suggestionEngineProvider);
  return engine.analyze(entries);
});
