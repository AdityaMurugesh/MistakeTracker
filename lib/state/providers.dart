// Owner: Reach & Data (initial setup) — every role adds their own providers here.
// Riverpod providers: DI container + reactive state.

import 'dart:async';

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

/// Real sqflite-backed DAO on native, in-memory stub on web.
/// sqflite + path_provider have no web implementation, so on web we keep the
/// app fully usable by storing entries in memory (lost on page refresh).
final entryDaoProvider = Provider<EntryDao>((ref) {
  if (kIsWeb) {
    final dao = _InMemoryEntryDao(_demoSeedEntries());
    ref.onDispose(dao.dispose);
    return dao;
  }
  final appDb = ref.watch(appDatabaseProvider);
  final dao = EntryDao(appDb.db);
  ref.onDispose(dao.dispose);
  return dao;
});

final entriesStreamProvider = StreamProvider<List<Entry>>((ref) {
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

// ---- Web fallback DAO -------------------------------------------------------

/// In-memory implementation of `EntryDao` used only on the web preview where
/// sqflite has no platform implementation. Behaviour matches the real DAO
/// closely enough for the Home / Insights flows to work end-to-end; data is
/// not persisted across page refreshes.
class _InMemoryEntryDao implements EntryDao {
  _InMemoryEntryDao(List<Entry> seed)
      : _entries = [...seed],
        _nextId = seed.fold<int>(
              0,
              (m, e) => (e.id ?? 0) > m ? e.id! : m,
            ) +
            1;

  final List<Entry> _entries;
  int _nextId;
  final StreamController<List<Entry>> _changes =
      StreamController<List<Entry>>.broadcast();

  @override
  Future<int> insert(Entry entry) async {
    final id = _nextId++;
    _entries.add(entry.copyWith(id: id));
    _emit();
    return id;
  }

  @override
  Future<void> update(Entry entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('Cannot update an Entry without an id');
    }
    final i = _entries.indexWhere((e) => e.id == id);
    if (i >= 0) _entries[i] = entry;
    _emit();
  }

  @override
  Future<void> delete(int id) async {
    _entries.removeWhere((e) => e.id == id);
    _emit();
  }

  @override
  Future<List<Entry>> getAll({int? limit, DateTime? since}) async {
    var list = [..._entries];
    list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (since != null) {
      list = list.where((e) => !e.occurredAt.isBefore(since)).toList();
    }
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<Entry?> getById(int id) async {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Stream<List<Entry>> watchAll() async* {
    yield await getAll();
    yield* _changes.stream;
  }

  void _emit() async {
    if (_changes.isClosed) return;
    _changes.add(await getAll());
  }

  @override
  Future<void> dispose() => _changes.close();
}

// ---- Demo seed (used by web fallback DAO and as a fixture for demos) -------

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
