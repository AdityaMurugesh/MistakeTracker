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

      final pattern =
          insights.where((i) => i.kind == InsightKind.pattern).toList();
      expect(pattern, hasLength(1));
      expect(pattern.first.title.toLowerCase(), contains('tired'));
      expect(pattern.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('2 entries with the same cause produce no pattern insight', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym', cause: 'tired', daysAgo: 2),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 5),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.pattern), isEmpty);
    });

    test('entries outside the 30-day window are ignored', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym', cause: 'tired', daysAgo: 2),
        mk(id: 2, what: 'missed gym', cause: 'tired', daysAgo: 5),
        mk(id: 3, what: 'missed gym', cause: 'tired', daysAgo: 45),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.pattern), isEmpty);
    });

    test('cause matching is case- and whitespace-insensitive', () async {
      final insights = await engine().analyze([
        mk(id: 1, cause: 'Tired', what: 'x', daysAgo: 1),
        mk(id: 2, cause: '  tired ', what: 'y', daysAgo: 2),
        mk(id: 3, cause: 'TIRED', what: 'z', daysAgo: 3),
      ]);
      final pattern =
          insights.where((i) => i.kind == InsightKind.pattern).toList();
      expect(pattern, hasLength(1));
      expect(pattern.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('null or empty cause is ignored', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', cause: null, daysAgo: 1),
        mk(id: 2, what: 'y', cause: '', daysAgo: 2),
        mk(id: 3, what: 'z', cause: '   ', daysAgo: 3),
      ]);
      expect(insights.where((i) => i.kind == InsightKind.pattern), isEmpty);
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
      final pattern =
          insights.firstWhere((i) => i.kind == InsightKind.pattern);
      expect(pattern.suggestion, equals('sleep before 11pm'));
    });

    test('no suggestion when user has not logged a solution', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', cause: 'tired', daysAgo: 1),
        mk(id: 2, what: 'y', cause: 'tired', daysAgo: 4),
        mk(id: 3, what: 'z', cause: 'tired', daysAgo: 8),
      ]);
      final pattern =
          insights.firstWhere((i) => i.kind == InsightKind.pattern);
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
      final pattern =
          insights.where((i) => i.kind == InsightKind.pattern).toList();
      expect(pattern, hasLength(2));
      expect(pattern[0].title.toLowerCase(), contains('tired'));
      expect(pattern[1].title.toLowerCase(), contains('bored'));
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
