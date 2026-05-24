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
  final now = DateTime.now();
  Entry mk({
    required int id,
    required String what,
    String? cause,
    String? solution,
    required int daysAgo,
    int hour = 9,
    int? costMinutes,
    int? costMoney,
  }) {
    final t = DateTime(now.year, now.month, now.day, hour)
        .subtract(Duration(days: daysAgo));
    return Entry(
      id: id,
      what: what,
      cause: cause,
      solution: solution,
      occurredAt: t,
      costMinutes: costMinutes,
      costMoney: costMoney,
      createdAt: t,
    );
  }

  return [
    mk(id: 1, what: 'missed workout', cause: 'tired', daysAgo: 2, hour: 7,
        solution: 'lay out gear the night before'),
    mk(id: 2, what: 'missed workout', cause: 'tired', daysAgo: 9, hour: 7),
    mk(id: 3, what: 'missed workout', cause: 'tired', daysAgo: 16, hour: 7),
    mk(id: 4, what: 'impulse purchase', cause: 'bored', daysAgo: 3,
        costMoney: 800),
    mk(id: 5, what: 'impulse purchase', cause: 'bored', daysAgo: 11,
        costMoney: 1200),
    mk(id: 6, what: 'impulse purchase', cause: 'bored', daysAgo: 20,
        costMoney: 400),
    mk(id: 7, what: 'skipped breakfast', daysAgo: 1, hour: 9, costMinutes: 20),
  ];
});

/// Insights for the current set of entries.
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  final entries = ref.watch(entriesProvider);
  final engine = ref.read(suggestionEngineProvider);
  return engine.analyze(entries);
});
