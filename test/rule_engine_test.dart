// Owner: Insights
// Unit tests for the brain of the app. Most important test file.

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/domain/models/entry.dart';
import 'package:mistake_tracker/domain/models/insight.dart';
import 'package:mistake_tracker/domain/rule_engine.dart';

void main() {
  // Frozen "now" so lookback-window tests are stable.
  final fixedNow = DateTime.utc(2026, 5, 24, 12, 0, 0);
  RuleEngine engine() => RuleEngine(now: () => fixedNow);

  Entry mk({
    int? id,
    required String what,
    String? cause,
    String? solution,
    DateTime? occurredAt,
    int daysAgo = 1,
    int? costMinutes,
    int? costMoney,
  }) {
    final occurred = occurredAt ?? fixedNow.subtract(Duration(days: daysAgo));
    return Entry(
      id: id,
      what: what,
      cause: cause,
      solution: solution,
      occurredAt: occurred,
      costMinutes: costMinutes,
      costMoney: costMoney,
      createdAt: occurred,
    );
  }

  group('RuleEngine — empty input', () {
    test('returns no insights for empty input', () async {
      final insights = await engine().analyze([]);
      expect(insights, isEmpty);
    });
  });

  group('RuleEngine — recurring cause', () {
    test('3 entries with the same cause produce one pattern insight', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym', cause: 'tired', daysAgo: 2),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 5),
        mk(id: 3, what: 'missed gym', cause: 'tired', daysAgo: 10),
      ]);

      final pattern = insights
          .where((i) =>
              i.kind == InsightKind.pattern && i.title.contains('tired'))
          .toList();
      expect(pattern, hasLength(1));
      expect(pattern.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('2 entries with the same cause produce no recurring-cause insight',
        () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym', cause: 'tired', daysAgo: 2),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 5),
      ]);
      expect(
          insights.where((i) => i.title.contains('tired')), isEmpty);
    });

    test('entries outside the 30-day window are ignored', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym', cause: 'tired', daysAgo: 2),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 5),
        mk(id: 3, what: 'missed gym', cause: 'tired', daysAgo: 45),
      ]);
      expect(
          insights.where((i) => i.title.contains('tired')), isEmpty);
    });

    test('cause matching is case- and whitespace-insensitive', () async {
      final insights = await engine().analyze([
        mk(id: 1, cause: 'Tired', what: 'x', daysAgo: 1),
        mk(id: 2, cause: '  tired ', what: 'y', daysAgo: 2),
        mk(id: 3, cause: 'TIRED', what: 'z', daysAgo: 3),
      ]);
      final pattern = insights
          .where((i) =>
              i.kind == InsightKind.pattern && i.title.contains('keeps'))
          .toList();
      expect(pattern, hasLength(1));
      expect(pattern.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('null or empty cause is ignored', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', cause: null, daysAgo: 1),
        mk(id: 2, what: 'y', cause: '', daysAgo: 2),
        mk(id: 3, what: 'z', cause: '   ', daysAgo: 3),
      ]);
      expect(insights.where((i) => i.title.contains('keeps')), isEmpty);
    });

    test("suggestion picks up user's own past solution", () async {
      final insights = await engine().analyze([
        mk(
          id: 1,
          what: 'missed gym',
          cause: 'tired',
          solution: 'sleep before 11pm',
          daysAgo: 1,
        ),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 4),
        mk(id: 3, what: 'missed gym', cause: 'tired', daysAgo: 8),
      ]);
      final pattern = insights
          .firstWhere((i) => i.title.contains('tired'));
      expect(pattern.suggestion, equals('sleep before 11pm'));
    });

    test('no suggestion when user has not logged a solution', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', cause: 'tired', daysAgo: 1),
        mk(id: 2, what: 'y', cause: 'tired', daysAgo: 4),
        mk(id: 3, what: 'z', cause: 'tired', daysAgo: 8),
      ]);
      final pattern = insights
          .firstWhere((i) => i.title.contains('tired'));
      expect(pattern.suggestion, isNull);
    });

    test('multiple qualifying causes both surface, sorted by count desc',
        () async {
      final insights = await engine().analyze([
        // 4 "tired"
        mk(id: 1, cause: 'tired', what: 'a', daysAgo: 1),
        mk(id: 2, cause: 'tired', what: 'b', daysAgo: 2),
        mk(id: 3, cause: 'tired', what: 'c', daysAgo: 3),
        mk(id: 4, cause: 'tired', what: 'd', daysAgo: 4),
        // 3 "bored"
        mk(id: 5, cause: 'bored', what: 'e', daysAgo: 1),
        mk(id: 6, cause: 'bored', what: 'f', daysAgo: 2),
        mk(id: 7, cause: 'bored', what: 'g', daysAgo: 3),
      ]);
      final pattern = insights
          .where((i) =>
              i.kind == InsightKind.pattern && i.title.contains('keeps'))
          .toList();
      expect(pattern, hasLength(2));
      expect(pattern[0].title.toLowerCase(), contains('tired'));
      expect(pattern[1].title.toLowerCase(), contains('bored'));
    });
  });

  group('RuleEngine — weekday pattern', () {
    // May 4, 11, 18, 2026 are all Mondays. Within 30d of fixedNow (May 24 2026).
    test('3 entries on same weekday + same what produce one insight',
        () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 9)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 11, 9)),
        mk(id: 3, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 18, 9)),
      ]);
      final wd = insights
          .where((i) => i.title.contains('Monday'))
          .toList();
      expect(wd, hasLength(1));
      expect(wd.first.kind, InsightKind.pattern);
      expect(wd.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('2 same-weekday entries do not trigger the rule', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 9)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 11, 9)),
      ]);
      expect(insights.where((i) => i.title.contains('Monday')), isEmpty);
    });

    test('different `what` does not collapse into one weekday group',
        () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 9)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 11, 9)),
        mk(id: 3, what: 'argument',
            occurredAt: DateTime(2026, 5, 18, 9)),
      ]);
      expect(insights.where((i) => i.title.contains('Monday')), isEmpty);
    });

    test('same what but different weekdays do not group', () async {
      final insights = await engine().analyze([
        // Mon, Tue, Wed
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 9)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 5, 9)),
        mk(id: 3, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 6, 9)),
      ]);
      expect(
          insights.where((i) =>
              i.kind == InsightKind.pattern &&
              i.title.contains('tends to happen on')),
          isEmpty);
    });
  });

  group('RuleEngine — hour pattern', () {
    test('3 entries at same hour + same what produce one insight', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 4, 21)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 11, 21)),
        mk(id: 3, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 18, 21)),
      ]);
      final h = insights
          .where((i) => i.title.contains('9 PM'))
          .toList();
      expect(h, hasLength(1));
      expect(h.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('different hours do not group', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 4, 21)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 11, 14)),
        mk(id: 3, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 18, 9)),
      ]);
      expect(
          insights.where((i) =>
              i.kind == InsightKind.pattern &&
              i.title.contains('tends to happen around')),
          isEmpty);
    });

    test('hour 0 formats as 12 AM, hour 12 as 12 PM', () async {
      final insights = await engine().analyze([
        // Midnight cluster
        mk(id: 1, what: 'late snack',
            occurredAt: DateTime(2026, 5, 4, 0)),
        mk(id: 2, what: 'late snack',
            occurredAt: DateTime(2026, 5, 11, 0)),
        mk(id: 3, what: 'late snack',
            occurredAt: DateTime(2026, 5, 18, 0)),
      ]);
      final h = insights.firstWhere((i) =>
          i.title.contains('tends to happen around'));
      expect(h.title, contains('12 AM'));
    });
  });

  group('RuleEngine — chain detection', () {
    // Three pairs of (A 23:00, B 02:00) on consecutive nights — gap is 3h,
    // inside the 6h chain window. Should fire one chain insight.
    test('3 occurrences of (A->B) within window produce one chain insight',
        () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 18, 23)),
        mk(id: 2, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 19, 2)),
        mk(id: 3, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 19, 23)),
        mk(id: 4, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 20, 2)),
        mk(id: 5, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 6, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 21, 2)),
      ]);
      final chains = insights
          .where((i) => i.kind == InsightKind.chain)
          .toList();
      expect(chains, hasLength(1));
      expect(chains.first.title.toLowerCase(),
          contains('late night scrolling'));
      expect(chains.first.title.toLowerCase(), contains('missed sleep'));
      expect(chains.first.evidenceIds, unorderedEquals([1, 2, 3, 4, 5, 6]));
    });

    test('gap larger than chainWindowHours breaks the chain', () async {
      // 8h between A and B — outside the 6h window.
      final insights = await engine().analyze([
        mk(id: 1, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 18, 23)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 19, 7)),
        mk(id: 3, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 19, 23)),
        mk(id: 4, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 20, 7)),
        mk(id: 5, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 6, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 21, 7)),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.chain), isEmpty);
    });

    test('2 occurrences are not enough to trigger', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 19, 23)),
        mk(id: 2, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 20, 2)),
        mk(id: 3, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 4, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 21, 2)),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.chain), isEmpty);
    });

    test('same-`what` consecutive entries are not surfaced as a chain',
        () async {
      // Three "missed workout" entries back to back within 6h of each other.
      // The chain rule must NOT emit "missed workout -> missed workout".
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 19, 7)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 19, 10)),
        mk(id: 3, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 19, 13)),
        mk(id: 4, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 19, 16)),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.chain), isEmpty);
    });

    test('A-side solution is surfaced as the suggestion', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'late night scrolling', solution: 'phone in kitchen',
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 2, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 21, 2)),
        mk(id: 3, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 21, 23)),
        mk(id: 4, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 22, 2)),
        mk(id: 5, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 22, 23)),
        mk(id: 6, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 23, 2)),
      ]);
      final chain =
          insights.firstWhere((i) => i.kind == InsightKind.chain);
      expect(chain.suggestion, equals('phone in kitchen'));
    });

    test('out-of-window entries do not appear in evidence ids', () async {
      // 4th pair lies > 30d before fixedNow, so the lookback filter excludes
      // entries 7 and 8 entirely. The chain still fires on the 3 in-window
      // pairs, and the evidence ids must contain ONLY in-window entry ids.
      final insights = await engine().analyze([
        mk(id: 1, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 18, 23)),
        mk(id: 2, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 19, 2)),
        mk(id: 3, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 19, 23)),
        mk(id: 4, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 20, 2)),
        mk(id: 5, what: 'late night scrolling',
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 6, what: 'missed sleep',
            occurredAt: DateTime(2026, 5, 21, 2)),
        // Out of window (more than 30 days before fixedNow May 24 2026).
        mk(id: 7, what: 'late night scrolling',
            occurredAt: DateTime(2026, 4, 1, 23)),
        mk(id: 8, what: 'missed sleep',
            occurredAt: DateTime(2026, 4, 2, 2)),
      ]);
      final chain =
          insights.firstWhere((i) => i.kind == InsightKind.chain);
      expect(chain.evidenceIds, isNot(contains(7)));
      expect(chain.evidenceIds, isNot(contains(8)));
      expect(chain.evidenceIds, unorderedEquals([1, 2, 3, 4, 5, 6]));
    });
  });

  group('RuleEngine — cost aggregation', () {
    test('sums costMinutes and costMoney across entries', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', costMinutes: 30, costMoney: 100, daysAgo: 1),
        mk(id: 2, what: 'y', costMinutes: 15, costMoney: 200, daysAgo: 5),
        mk(id: 3, what: 'z', daysAgo: 10),
      ]);
      final cost = insights.firstWhere((i) => i.kind == InsightKind.cost);
      expect(cost.body, contains('300'));
      expect(cost.body, contains('45'));
      expect(cost.evidenceIds, unorderedEquals([1, 2]));
    });

    test('no cost insight when all costs are null or zero', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', daysAgo: 1),
        mk(id: 2, what: 'y', costMinutes: 0, costMoney: 0, daysAgo: 2),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.cost), isEmpty);
    });

    test('cost entries older than lookback window are ignored', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', costMoney: 999, daysAgo: 45),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.cost), isEmpty);
    });
  });
}
