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

import '../domain/models/insight.dart';
import '../domain/rule_engine.dart';
import '../domain/suggestion_engine.dart';

// --- Insights providers ---

final suggestionEngineProvider = Provider<SuggestionEngine>((ref) {
  return RuleEngine();
});

/// Insights for the current set of entries.
///
/// Stage 1 (now): returns hardcoded Insights so the Insights screen has cards
/// to render before Capture's entry stream is wired up.
/// Stage 2+: switch to `engine.analyze(entries)` once `entriesStreamProvider`
/// exists.
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  // TODO(insights): replace with engine.analyze(entries) once entriesStreamProvider lands.
  // final entries = await ref.watch(entriesStreamProvider.future);
  // return ref.read(suggestionEngineProvider).analyze(entries);
  return const [
    Insight(
      kind: InsightKind.pattern,
      title: 'Missed workouts cluster on Mondays',
      body: '4 of your last 6 skipped workouts happened on a Monday.',
      evidenceIds: [],
      suggestion: 'Try moving Monday workouts to evening or lay out gear Sunday night.',
    ),
    Insight(
      kind: InsightKind.chain,
      title: 'Late night → late morning',
      body: 'Sleeping past 1am is followed by skipping breakfast 5 times this month.',
      evidenceIds: [],
      suggestion: 'Set a wind-down alarm at 11:30pm.',
    ),
    Insight(
      kind: InsightKind.cost,
      title: 'Impulse purchases this month',
      body: '6 impulse purchases logged, totalling about ₹2,400.',
      evidenceIds: [],
    ),
  ];
});
