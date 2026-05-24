// Owner: Reach & Data (initial setup) — every role adds their own providers here.
// Riverpod providers: DI container + reactive state.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/entry_dao.dart';
import '../domain/models/entry.dart';
import '../domain/models/insight.dart';
import '../domain/rule_engine.dart';
import '../domain/suggestion_engine.dart';

// ---- Capture ----------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase.instance);

final entryDaoProvider = Provider<EntryDao>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  final dao = EntryDao(appDb.db);
  ref.onDispose(dao.dispose);
  return dao;
});

/// Reactive list of entries the user has logged.
///
/// On native (Android/iOS/desktop) this watches the real sqflite-backed DAO.
/// On web, sqflite has no implementation, so we fall back to a stable seed
/// of demo entries so the Insights screen still renders something for a
/// browser-based preview.
final entriesStreamProvider = StreamProvider<List<Entry>>((ref) {
  if (kIsWeb) {
    return Stream.value(_demoSeedEntries());
  }
  return ref.watch(entryDaoProvider).watchAll();
});

// ---- Insights ---------------------------------------------------------------

final suggestionEngineProvider = Provider<SuggestionEngine>((ref) {
  return RuleEngine();
});

/// Insights derived from the current entries via the rule engine.
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  final entries = await ref.watch(entriesStreamProvider.future);
  final engine = ref.read(suggestionEngineProvider);
  return engine.analyze(entries);
});

// ---- Reach & Data -----------------------------------------------------------
// (exportServiceProvider, notifierProvider, timeSignalProvider go here)

// ---- Demo seed (web-only fallback) ------------------------------------------

List<Entry> _demoSeedEntries() {
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
}
