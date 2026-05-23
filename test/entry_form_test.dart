// Owner: Capture
// Widget tests for the entry form — the most important UX surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/data/entry_dao.dart';
import 'package:mistake_tracker/domain/models/entry.dart';
import 'package:mistake_tracker/state/providers.dart';
import 'package:mistake_tracker/ui/entry_form.dart';
import 'package:mocktail/mocktail.dart';

class _MockEntryDao extends Mock implements EntryDao {}

Entry _sampleEntry({int? id, String what = 'sample', int severity = 3}) {
  final now = DateTime.utc(2026, 1, 1, 12, 0);
  return Entry(
    id: id,
    what: what,
    occurredAt: now,
    severity: severity,
    createdAt: now,
  );
}

Widget _harness({required EntryDao dao, Entry? existing}) {
  return ProviderScope(
    overrides: [entryDaoProvider.overrideWithValue(dao)],
    child: MaterialApp(home: EntryForm(existing: existing)),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_sampleEntry());
  });

  group('EntryForm — create mode', () {
    testWidgets('shows Required error and does not insert when What is empty',
        (tester) async {
      final dao = _MockEntryDao();
      await tester.pumpWidget(_harness(dao: dao));

      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      verifyNever(() => dao.insert(any()));
    });

    testWidgets('calls EntryDao.insert with trimmed What on save',
        (tester) async {
      final dao = _MockEntryDao();
      when(() => dao.insert(any())).thenAnswer((_) async => 1);

      await tester.pumpWidget(_harness(dao: dao));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'What happened *'),
        '  Missed gym  ',
      );
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      final captured =
          verify(() => dao.insert(captureAny())).captured.single as Entry;
      expect(captured.what, 'Missed gym');
      expect(captured.severity, 3);
      expect(captured.id, isNull);
    });

    testWidgets('keeps user on form and shows SnackBar when insert throws',
        (tester) async {
      final dao = _MockEntryDao();
      when(() => dao.insert(any())).thenThrow(Exception('disk full'));

      await tester.pumpWidget(_harness(dao: dao));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'What happened *'),
        'x',
      );
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't save entry"), findsOneWidget);
      expect(find.text('Log a failure'), findsOneWidget); // still on form
    });
  });

  group('EntryForm — edit mode', () {
    testWidgets('pre-fills fields from the existing entry', (tester) async {
      final dao = _MockEntryDao();
      final entry = _sampleEntry(id: 7, what: 'Skipped run', severity: 4);

      await tester.pumpWidget(_harness(dao: dao, existing: entry));
      await tester.pumpAndSettle();

      expect(find.text('Skipped run'), findsOneWidget);
      expect(find.text('4 / 5'), findsOneWidget);
      expect(find.text('Edit entry'), findsOneWidget);
    });

    testWidgets('calls EntryDao.update with the same id on save',
        (tester) async {
      final dao = _MockEntryDao();
      when(() => dao.update(any())).thenAnswer((_) async {});
      final entry = _sampleEntry(id: 42, what: 'Original');

      await tester.pumpWidget(_harness(dao: dao, existing: entry));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'What happened *'),
        'Updated',
      );
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      final captured =
          verify(() => dao.update(captureAny())).captured.single as Entry;
      expect(captured.id, 42);
      expect(captured.what, 'Updated');
    });

    testWidgets('delete calls EntryDao.delete after confirm', (tester) async {
      final dao = _MockEntryDao();
      when(() => dao.delete(any())).thenAnswer((_) async {});
      final entry = _sampleEntry(id: 13);

      await tester.pumpWidget(_harness(dao: dao, existing: entry));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => dao.delete(13)).called(1);
    });

    testWidgets('delete cancel does not call EntryDao.delete', (tester) async {
      final dao = _MockEntryDao();
      final entry = _sampleEntry(id: 13);

      await tester.pumpWidget(_harness(dao: dao, existing: entry));
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => dao.delete(any()));
    });
  });
}
