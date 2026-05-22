// Owner: Capture
// Opens sqflite, runs migrations. Single source of database access.
//
// TODO:
//   - Open DB at <documents>/mistake_tracker.db via path_provider
//   - Create `entries` table matching Entry.toMap() column names
//   - Add index on occurred_at (for time-pattern queries)
//   - Schema migration scaffolding so v2 can add columns

import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    throw UnimplementedError('AppDatabase.db not implemented');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
