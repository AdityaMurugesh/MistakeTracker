// Owner: Reach & Data (initial setup) — but every role adds their own providers here.
// Riverpod providers: DI container + reactive state.
//
// TODO (Day 1 shared setup):
//   - appDatabaseProvider     -> AppDatabase.instance
//   - entryDaoProvider        -> EntryDao(db)
//   - suggestionEngineProvider -> RuleEngine() (typed as SuggestionEngine)
//   - exportServiceProvider   -> ExportService(dao)
//   - notifierProvider        -> Notifier()
//   - timeSignalProvider      -> TimeSignal(dao)
//
// Reactive providers each role adds:
//   - entriesStreamProvider   (Capture)
//   - insightsProvider        (Insights — recomputed when entries change)

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/entry_dao.dart';
import '../data/export_service.dart';
import '../notifications/time_signal.dart';
import '../notifications/notifier.dart';

/// Entry DAO provider. Capture role should implement the DAO methods.
final entryDaoProvider = Provider<EntryDao>((ref) => EntryDao());

/// ExportService wired to the DAO
final exportServiceProvider = Provider<ExportService>((ref) => ExportService(ref.read(entryDaoProvider)));

/// TimeSignal provider (depends on DAO)
final timeSignalProvider = Provider<TimeSignal>((ref) => TimeSignal(ref.read(entryDaoProvider)));

/// Notifier (handles permission, scheduling). Init called from the app shell.
final notifierProvider = Provider<LocalNotifier>((ref) => LocalNotifier());

/// Local UI flag for whether notifications are enabled (registration done)
final notificationsEnabledProvider = StateProvider<bool>((ref) => false);
