// Owner: Reach & Data (initial setup) — every role adds their own providers here.
// Riverpod providers: DI container + reactive state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/entry_dao.dart';
import '../domain/models/entry.dart';

// ---- Capture ----------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase.instance);

final entryDaoProvider = Provider<EntryDao>((ref) {
  final dao = EntryDao(ref.watch(appDatabaseProvider));
  ref.onDispose(dao.dispose);
  return dao;
});

final entriesStreamProvider = StreamProvider<List<Entry>>((ref) {
  return ref.watch(entryDaoProvider).watchAll();
});

// ---- Insights ---------------------------------------------------------------
// (insightsProvider goes here)

// ---- Reach & Data -----------------------------------------------------------
// (suggestionEngineProvider, exportServiceProvider, notifierProvider,
//  timeSignalProvider go here)
