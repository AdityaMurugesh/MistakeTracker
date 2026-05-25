// Owner: Reach & Data (initial setup) — every role adds their own providers here.
// Riverpod providers: DI container + reactive state.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/entry_dao.dart';
import '../data/export_service.dart';
import '../domain/models/entry.dart';
import '../domain/models/forecast.dart';
import '../domain/models/insight.dart';
import '../domain/fallback_narrative_engine.dart';
import '../domain/fallback_outlook_engine.dart';
import '../domain/fallback_suggestion_engine.dart';
import '../domain/narrative_engine.dart';
import '../domain/ollama_suggestion_engine.dart';
import '../domain/outlook_engine.dart';
import '../domain/rule_engine.dart';
import '../domain/suggestion_engine.dart';
import '../notifications/notifier.dart';
import '../notifications/time_signal.dart';

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

/// Concrete RuleEngine — also used directly for features beyond the
/// SuggestionEngine contract (forecasts, narrative).
final ruleEngineProvider = Provider<RuleEngine>((ref) => RuleEngine());

/// Single OllamaSuggestionEngine instance shared between the
/// SuggestionEngine and NarrativeEngine seams — one engine, one HTTP client,
/// two interfaces.
final _ollamaEngineProvider = Provider<OllamaSuggestionEngine?>((ref) {
  final ai = ref.watch(aiSettingsProvider);
  if (!ai.enabled || kIsWeb) return null;
  final ollama = OllamaSuggestionEngine(host: ai.host, model: ai.model);
  ref.onDispose(ollama.dispose);
  return ollama;
});

/// Active SuggestionEngine. When AI insights are off, this is the RuleEngine
/// directly. When on, it's an OllamaSuggestionEngine wrapped in a fallback
/// that drops to RuleEngine on any error — so the Insights screen never
/// breaks even if Ollama isn't running.
final suggestionEngineProvider = Provider<SuggestionEngine>((ref) {
  final rule = ref.watch(ruleEngineProvider);
  final ollama = ref.watch(_ollamaEngineProvider);
  if (ollama == null) return rule;
  return FallbackSuggestionEngine(primary: ollama, fallback: rule);
});

/// Active NarrativeEngine. Same swap pattern as suggestionEngineProvider,
/// but for the hero card's one-paragraph summary.
final narrativeEngineProvider = Provider<NarrativeEngine>((ref) {
  final rule = ref.watch(ruleEngineProvider);
  final ollama = ref.watch(_ollamaEngineProvider);
  if (ollama == null) return rule;
  return FallbackNarrativeEngine(primary: ollama, fallback: rule);
});

/// Active OutlookEngine. RuleEngine returns null for outlook so the card
/// stays hidden when AI is off; when on, the LLM writes a forward-looking
/// "heads up" paragraph and falls back to null on error.
final outlookEngineProvider = Provider<OutlookEngine>((ref) {
  final rule = ref.watch(ruleEngineProvider);
  final ollama = ref.watch(_ollamaEngineProvider);
  if (ollama == null) return rule;
  return FallbackOutlookEngine(primary: ollama, fallback: rule);
});

/// Insights derived from the current entries via the active suggestion engine.
/// Watches the engine provider so flipping AI insights on/off re-runs analyze().
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  final entries = await ref.watch(entriesStreamProvider.future);
  final engine = ref.watch(suggestionEngineProvider);
  return engine.analyze(entries);
});

/// Forward-looking projections from the rule engine. Sorted soonest-first.
final forecastsProvider = FutureProvider<List<Forecast>>((ref) async {
  final entries = await ref.watch(entriesStreamProvider.future);
  final engine = ref.read(ruleEngineProvider);
  return engine.forecast(entries);
});

/// Short narrative summary of the last 7 days. Null when there's no
/// recent activity. Watches the engine provider so flipping AI insights on
/// re-runs the narrative through the LLM.
final narrativeProvider = FutureProvider<String?>((ref) async {
  final entries = await ref.watch(entriesStreamProvider.future);
  final engine = ref.watch(narrativeEngineProvider);
  return engine.narrative(entries);
});

/// Forward-looking "heads up" paragraph derived from entries + forecasts.
/// Null when the active engine has nothing to say (AI off, or AI errored).
final outlookProvider = FutureProvider<String?>((ref) async {
  final entries = await ref.watch(entriesStreamProvider.future);
  final forecasts = await ref.watch(forecastsProvider.future);
  final engine = ref.watch(outlookEngineProvider);
  return engine.outlook(entries, forecasts);
});

// ---- Reach & Data -----------------------------------------------------------

/// JSON export of entries via `share_plus`.
final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.read(entryDaoProvider)),
);

/// Detects time-of-day patterns and emits notification triggers.
final timeSignalProvider = Provider<TimeSignal>(
  (ref) => TimeSignal(ref.read(entryDaoProvider)),
);

/// Local notifications glue (permission handling + scheduling).
final notifierProvider = Provider<LocalNotifier>((ref) => LocalNotifier());

/// UI flag: whether the user has granted notification permission.
final notificationsEnabledProvider = StateProvider<bool>((ref) => false);

// ---- Theme mode persistence ------------------------------------------------

const _kThemeModeKey = 'theme_mode';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kThemeModeKey) ?? 'system';
      state = _fromString(stored);
    } catch (_) {
      // ignore errors and stay on system
    }
  }

  ThemeMode _fromString(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
      default:
        return 'system';
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _toString(mode));
    } catch (_) {
      // ignore persistence errors
    }
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());

// ---- AI insights settings ---------------------------------------------------

/// On-device default for the Android emulator: 10.0.2.2 is the host machine
/// where Ollama is running. Override in Settings for a real device or a
/// different host.
const _kAiDefaultHost = 'http://10.0.2.2:11434';
const _kAiDefaultModel = 'llama3.2';
const _kAiEnabledKey = 'ai_enabled';
const _kAiHostKey = 'ai_host';
const _kAiModelKey = 'ai_model';

class AiSettings {
  final bool enabled;
  final String host;
  final String model;
  const AiSettings({required this.enabled, required this.host, required this.model});

  AiSettings copyWith({bool? enabled, String? host, String? model}) =>
      AiSettings(
        enabled: enabled ?? this.enabled,
        host: host ?? this.host,
        model: model ?? this.model,
      );
}

class AiSettingsNotifier extends StateNotifier<AiSettings> {
  AiSettingsNotifier()
      : super(const AiSettings(
          enabled: false,
          host: _kAiDefaultHost,
          model: _kAiDefaultModel,
        )) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AiSettings(
        enabled: prefs.getBool(_kAiEnabledKey) ?? false,
        host: prefs.getString(_kAiHostKey) ?? _kAiDefaultHost,
        model: prefs.getString(_kAiModelKey) ?? _kAiDefaultModel,
      );
    } catch (_) {
      // keep defaults
    }
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAiEnabledKey, v);
  }

  Future<void> setHost(String v) async {
    state = state.copyWith(host: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiHostKey, v);
  }

  Future<void> setModel(String v) async {
    state = state.copyWith(model: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiModelKey, v);
  }
}

final aiSettingsProvider =
    StateNotifierProvider<AiSettingsNotifier, AiSettings>(
        (ref) => AiSettingsNotifier());

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

// ---- Debug seeding ----------------------------------------------------------

/// Call from main() before runApp(). On debug builds running on a native
/// platform with an empty entries table, this populates the table with the
/// demo seed so the app opens to a fully-loaded Insights screen instead of
/// an empty one. No-op on web (web has its own in-memory seeded DAO), no-op
/// on release builds, no-op if any entries already exist.
Future<void> seedIfDebugAndEmpty() async {
  if (kIsWeb || !kDebugMode) return;
  final dao = EntryDao(AppDatabase.instance.db);
  try {
    final existing = await dao.getAll(limit: 1);
    if (existing.isNotEmpty) return;
    for (final e in _demoSeedEntries()) {
      await dao.insert(e);
    }
  } finally {
    await dao.dispose();
  }
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

  // Missed workouts: Mondays 7am, last 3 weeks. Triggers recurring-cause,
  // weekday pattern (Monday), and hour pattern (7 AM). The cause is phrased
  // three different ways (tired / exhausted / drained) on purpose — the
  // semantic layer should merge them into one "tired" pattern instead of
  // leaving each at count 1. Two of the three `what`s are phrased differently
  // too (skipped workout / no gym today) so the weekday/hour rule has to
  // bridge "missed workout" ≈ "skipped workout" ≈ "no gym today" via
  // conceptKey.
  const workoutPhrasings = [
    ('missed workout', 'tired', 'lay out gear the night before'),
    ('skipped workout', 'exhausted', null),
    ('no gym today', 'drained', null),
  ];
  for (var w = 0; w < 3; w++) {
    final p = workoutPhrasings[w];
    entries.add(mk(
      id: entries.length + 1,
      what: p.$1,
      cause: p.$2,
      occurredAt: atRecentWeekday(monday, 7, weeksAgo: w),
      solution: p.$3,
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

  // Cascade seed: a 3-step chain of "argument with roommate" -> "couldn't
  // sleep" -> "missed run", three weeks running. Weekdays vary across the
  // triples so this only fires the chain / multi-step rules, not weekday
  // or hour patterns. The "missed run" steps share the workout concept key
  // with the Monday cluster above, which lets the RAG suggestion path
  // surface the user's "lay out gear" solution on the cascade card.
  const cascadeRows = <(int, int, int, int)>[
    // (weekday, trigger hr, consequence hr, next-day-step hr)
    (2, 20, 23, 5), // Tue 8 PM → Tue 11 PM → Wed 5 AM
    (3, 19, 23, 5), // Wed 7 PM → Wed 11 PM → Thu 5 AM
    (4, 21, 23, 5), // Thu 9 PM → Thu 11 PM → Fri 5 AM
  ];
  for (var w = 0; w < cascadeRows.length; w++) {
    final row = cascadeRows[w];
    final triggerWd = row.$1;
    final nextDayWd = (triggerWd % 7) + 1;
    entries.add(mk(
      id: entries.length + 1,
      what: 'argument with roommate',
      occurredAt: atRecentWeekday(triggerWd, row.$2, weeksAgo: w),
      solution: w == 0 ? 'walk it off before bed' : null,
    ));
    entries.add(mk(
      id: entries.length + 1,
      what: "couldn't sleep",
      occurredAt: atRecentWeekday(triggerWd, row.$3, weeksAgo: w),
      costMinutes: 60,
    ));
    entries.add(mk(
      id: entries.length + 1,
      what: 'missed run',
      occurredAt: atRecentWeekday(nextDayWd, row.$4, weeksAgo: w),
    ));
  }

  return entries;
}
