// Owner: Capture
// Only this file touches the `entries` table directly.
//
// TODO:
//   - insert(Entry) -> int id
//   - update(Entry)
//   - delete(int id)
//   - getAll({int? limit, DateTime? since}) -> List<Entry>
//   - getById(int id) -> Entry?
//   - watchAll() -> Stream<List<Entry>>   (for reactive UI)

import '../domain/models/entry.dart';

class EntryDao {
  Future<int> insert(Entry entry) async {
    throw UnimplementedError();
  }

  Future<void> update(Entry entry) async {
    throw UnimplementedError();
  }

  Future<void> delete(int id) async {
    throw UnimplementedError();
  }

  Future<List<Entry>> getAll({int? limit, DateTime? since}) async {
    throw UnimplementedError();
  }

  Future<Entry?> getById(int id) async {
    throw UnimplementedError();
  }

  Stream<List<Entry>> watchAll() {
    throw UnimplementedError();
  }
}
