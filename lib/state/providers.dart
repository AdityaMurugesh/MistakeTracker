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

// Placeholder — replace with real providers as modules come online.
final placeholderProvider = Provider<String>((ref) => 'TODO: wire providers');
