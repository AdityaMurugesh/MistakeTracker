// Owner: Capture
// Widget tests for the recent-entries list + FAB.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/domain/models/entry.dart';
import 'package:mistake_tracker/state/providers.dart';
import 'package:mistake_tracker/ui/entry_form.dart';
import 'package:mistake_tracker/ui/home_screen.dart';

Entry _entry({
  int id = 1,
  String what = 'sample',
  int severity = 3,
  DateTime? occurredAt,
}) {
  final t = occurredAt ?? DateTime.utc(2026, 1, 1, 12, 0);
  return Entry(
    id: id,
    what: what,
    occurredAt: t,
    severity: severity,
    createdAt: t,
  );
}

Widget _harness(Stream<List<Entry>> stream) {
  return ProviderScope(
    overrides: [entriesStreamProvider.overrideWith((_) => stream)],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  group('HomeScreen', () {
    testWidgets('shows empty state when no entries', (tester) async {
      await tester.pumpWidget(_harness(Stream.value(const <Entry>[])));
      await tester.pumpAndSettle();

      expect(
        find.text('No entries yet — tap + to log your first failure.'),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('renders each entry with what + severity', (tester) async {
      await tester.pumpWidget(
        _harness(Stream.value([
          _entry(id: 1, what: 'Missed gym', severity: 4),
          _entry(id: 2, what: 'Late to meeting', severity: 2),
        ])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Missed gym'), findsOneWidget);
      expect(find.text('Late to meeting'), findsOneWidget);
      expect(find.textContaining('severity 4'), findsOneWidget);
      expect(find.textContaining('severity 2'), findsOneWidget);
    });

    testWidgets('FAB opens EntryForm in create mode', (tester) async {
      await tester.pumpWidget(_harness(Stream.value(const <Entry>[])));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.byType(EntryForm), findsOneWidget);
      expect(find.text('Log a failure'), findsOneWidget);
    });

    testWidgets('tapping an entry opens EntryForm in edit mode',
        (tester) async {
      await tester.pumpWidget(
        _harness(Stream.value([_entry(id: 7, what: 'Skipped run')])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skipped run'));
      await tester.pumpAndSettle();

      expect(find.byType(EntryForm), findsOneWidget);
      expect(find.text('Edit entry'), findsOneWidget);
    });

    testWidgets('shows loading indicator before stream emits',
        (tester) async {
      final controller = StreamController<List<Entry>>();
      await tester.pumpWidget(_harness(controller.stream));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await controller.close();
    });

    testWidgets('shows error UI when stream errors', (tester) async {
      await tester.pumpWidget(
        _harness(Stream.error('boom')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Error: boom'), findsOneWidget);
    });
  });
}
