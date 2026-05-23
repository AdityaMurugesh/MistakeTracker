// Owner: Capture
// Only this file touches the `entries` table directly.

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../domain/models/entry.dart';

class EntryDao {
  EntryDao(this._dbFuture);

  final Future<Database> _dbFuture;
  final StreamController<List<Entry>> _changes =
      StreamController<List<Entry>>.broadcast();

  Future<Database> _db() => _dbFuture;

  Future<int> insert(Entry entry) async {
    final db = await _db();
    final values = entry.toMap()..remove('id');
    final id = await db.insert('entries', values);
    await _emit();
    return id;
  }

  Future<void> update(Entry entry) async {
    final id = entry.id;
    if (id == null) {
      throw ArgumentError('Cannot update an Entry without an id');
    }
    final db = await _db();
    await db.update(
      'entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    await _emit();
  }

  Future<void> delete(int id) async {
    final db = await _db();
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
    await _emit();
  }

  Future<List<Entry>> getAll({int? limit, DateTime? since}) async {
    final db = await _db();
    final rows = await db.query(
      'entries',
      where: since != null ? 'occurred_at >= ?' : null,
      whereArgs: since != null ? [since.toUtc().toIso8601String()] : null,
      orderBy: 'occurred_at DESC',
      limit: limit,
    );
    return rows.map(Entry.fromMap).toList();
  }

  Future<Entry?> getById(int id) async {
    final db = await _db();
    final rows = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Entry.fromMap(rows.first);
  }

  Stream<List<Entry>> watchAll() async* {
    yield await getAll();
    yield* _changes.stream;
  }

  Future<void> _emit() async {
    if (_changes.isClosed) return;
    _changes.add(await getAll());
  }

  Future<void> dispose() => _changes.close();
}
