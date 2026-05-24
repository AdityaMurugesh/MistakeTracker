// Owner: Capture
// Opens sqflite, runs migrations. Single source of database access.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'mistake_tracker.db';
  static const _version = 1;

  Database? _db;

  Future<Database> get db async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) => createEntriesSchema(db);

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2 migrations land here (e.g. ALTER TABLE for win-log fields).
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

/// Creates the v1 `entries` table and its indexes on a fresh database.
/// Extracted so unit tests can run it against an in-memory sqflite_ffi DB.
Future<void> createEntriesSchema(Database db) async {
  await db.execute('''
    CREATE TABLE entries (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      kind          TEXT    NOT NULL DEFAULT 'failure',
      what          TEXT    NOT NULL,
      cause         TEXT,
      occurred_at   TEXT    NOT NULL,
      context       TEXT,
      severity      INTEGER NOT NULL DEFAULT 3,
      cost_minutes  INTEGER,
      cost_money    INTEGER,
      mood_impact   TEXT,
      solution      TEXT,
      created_at    TEXT    NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_entries_occurred_at ON entries(occurred_at)',
  );
}
