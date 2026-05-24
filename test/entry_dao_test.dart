// Owner: Capture
// Integration tests for the EntryDao against an in-memory sqflite_ffi DB.
// Verifies CRUD semantics and watchAll stream behaviour.

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/data/database.dart';
import 'package:mistake_tracker/data/entry_dao.dart';
import 'package:mistake_tracker/domain/models/entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Entry _mk({
  int? id,
  String what = 'sample',
  DateTime? occurredAt,
  int severity = 3,
  String? cause,
}) {
  final t = occurredAt ?? DateTime.utc(2026, 1, 1, 12, 0);
  return Entry(
    id: id,
    what: what,
    cause: cause,
    occurredAt: t,
    severity: severity,
    createdAt: DateTime.utc(2026, 1, 1, 0, 0),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;
  late EntryDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createEntriesSchema(db);
    dao = EntryDao(Future.value(db));
  });

  tearDown(() async {
    await dao.dispose();
    await db.close();
  });

  group('EntryDao CRUD', () {
    test('insert returns positive id and stores the row', () async {
      final id = await dao.insert(_mk(what: 'Missed gym'));

      expect(id, greaterThan(0));
      final all = await dao.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(all.single.what, 'Missed gym');
    });

    test('insert ignores any id passed in (autoincrement wins)', () async {
      final id1 = await dao.insert(_mk(id: 999, what: 'a'));
      final id2 = await dao.insert(_mk(id: 999, what: 'b'));
      expect(id1, isNot(equals(999)));
      expect(id2, isNot(equals(id1)));
    });

    test('getById returns the entry or null', () async {
      final id = await dao.insert(_mk(what: 'Skipped run', cause: 'tired'));

      final found = await dao.getById(id);
      expect(found, isNotNull);
      expect(found!.what, 'Skipped run');
      expect(found.cause, 'tired');

      expect(await dao.getById(99999), isNull);
    });

    test('getAll orders newest occurred_at first', () async {
      await dao.insert(_mk(
        what: 'oldest',
        occurredAt: DateTime.utc(2026, 1, 1),
      ));
      await dao.insert(_mk(
        what: 'newest',
        occurredAt: DateTime.utc(2026, 5, 1),
      ));
      await dao.insert(_mk(
        what: 'middle',
        occurredAt: DateTime.utc(2026, 3, 1),
      ));

      final ordered = await dao.getAll();
      expect(ordered.map((e) => e.what).toList(),
          ['newest', 'middle', 'oldest']);
    });

    test('getAll honours since filter and limit', () async {
      for (var month = 1; month <= 5; month++) {
        await dao.insert(_mk(
          what: 'month-$month',
          occurredAt: DateTime.utc(2026, month, 1),
        ));
      }

      final sinceMar = await dao.getAll(since: DateTime.utc(2026, 3, 1));
      expect(sinceMar.map((e) => e.what).toList(),
          ['month-5', 'month-4', 'month-3']);

      final limited = await dao.getAll(limit: 2);
      expect(limited, hasLength(2));
    });

    test('update writes the new values for the same id', () async {
      final id = await dao.insert(_mk(what: 'before', severity: 2));
      final original = (await dao.getById(id))!;

      await dao.update(original.copyWith(what: 'after', severity: 5));

      final after = (await dao.getById(id))!;
      expect(after.what, 'after');
      expect(after.severity, 5);
      expect(after.id, id);
    });

    test('update without an id throws', () async {
      expect(
        () => dao.update(_mk(what: 'no id')),
        throwsArgumentError,
      );
    });

    test('delete removes the row', () async {
      final id = await dao.insert(_mk());
      expect(await dao.getAll(), hasLength(1));

      await dao.delete(id);
      expect(await dao.getAll(), isEmpty);
    });
  });

  group('EntryDao watchAll', () {
    test('emits an initial snapshot of current entries', () async {
      await dao.insert(_mk(what: 'first'));

      final list = await dao.watchAll().first;
      expect(list.map((e) => e.what).toList(), ['first']);
    });

    test('re-emits after insert / update / delete', () async {
      final emissions = <List<Entry>>[];
      final sub = dao.watchAll().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final id = await dao.insert(_mk(what: 'first'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final original = (await dao.getById(id))!;
      await dao.update(original.copyWith(what: 'first edited'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await dao.delete(id);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await sub.cancel();

      expect(emissions, hasLength(greaterThanOrEqualTo(4)));
      expect(emissions.first, isEmpty);
      expect(emissions.last, isEmpty);
      expect(
        emissions.any((e) => e.length == 1 && e.single.what == 'first'),
        isTrue,
      );
      expect(
        emissions.any(
          (e) => e.length == 1 && e.single.what == 'first edited',
        ),
        isTrue,
      );
    });
  });
}
