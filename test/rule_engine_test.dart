// Owner: Insights
// Unit tests for the brain of the app. Most important test file.

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/domain/models/entry.dart';
import 'package:mistake_tracker/domain/models/forecast.dart';
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

    test('body includes a yearly projection', () async {
      // $300 / 30d = $10/day => ~$3650/year.
      // 45min / 30d = 1.5min/day => ~547min/year => ~9 hours.
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', costMinutes: 30, costMoney: 100, daysAgo: 1),
        mk(id: 2, what: 'y', costMinutes: 15, costMoney: 200, daysAgo: 5),
      ]);
      final cost = insights.firstWhere((i) => i.kind == InsightKind.cost);
      expect(cost.body.toLowerCase(), contains('rate'));
      expect(cost.body, contains('3650'));
      expect(cost.body, contains('9 hours'));
    });
  });

  group('RuleEngine — cross-cause correlation', () {
    // (cause: stressed) -> (what: impulse purchase) within 24h, 3 weeks running.
    test('3 occurrences of (cause -> what) within 24h fire a chain insight',
        () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 19, 18)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 20, 8)),
        mk(id: 3, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 20, 18)),
        mk(id: 4, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 21, 8)),
        mk(id: 5, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 21, 18)),
        mk(id: 6, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 22, 8)),
      ]);
      final cross = insights.where((i) =>
          i.kind == InsightKind.chain &&
          i.title.toLowerCase().contains('when the cause is')).toList();
      expect(cross, hasLength(1));
      expect(cross.first.title.toLowerCase(), contains('stressed'));
      expect(cross.first.title.toLowerCase(), contains('impulse purchase'));
      expect(cross.first.evidenceIds, unorderedEquals([1, 2, 3, 4, 5, 6]));
    });

    test('gap larger than 24h breaks the cross-cause correlation', () async {
      // 30h between trigger and consequence.
      final insights = await engine().analyze([
        mk(id: 1, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 18, 8)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 19, 14)),
        mk(id: 3, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 19, 8)),
        mk(id: 4, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 20, 14)),
        mk(id: 5, what: 'argument', cause: 'stressed',
            occurredAt: DateTime(2026, 5, 20, 8)),
        mk(id: 6, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 21, 14)),
      ]);
      expect(
          insights.where(
              (i) => i.title.toLowerCase().contains('when the cause is')),
          isEmpty);
    });

    test('cross-cause requires a non-null cause on the trigger', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'argument', cause: null,
            occurredAt: DateTime(2026, 5, 19, 18)),
        mk(id: 2, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 20, 8)),
        mk(id: 3, what: 'argument', cause: null,
            occurredAt: DateTime(2026, 5, 20, 18)),
        mk(id: 4, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 21, 8)),
        mk(id: 5, what: 'argument', cause: null,
            occurredAt: DateTime(2026, 5, 21, 18)),
        mk(id: 6, what: 'impulse purchase',
            occurredAt: DateTime(2026, 5, 22, 8)),
      ]);
      expect(
          insights.where(
              (i) => i.title.toLowerCase().contains('when the cause is')),
          isEmpty);
    });
  });

  group('RuleEngine — streak / improvement', () {
    test('long quiet stretch after a recurring `what` emits improvement',
        () async {
      // 5 entries spaced ~3 days apart, last one 14 days ago. Avg gap ~3d,
      // daysSince=14 > 7 (min) and > 2*3=6 → improvement should fire.
      final insights = await engine().analyze([
        mk(id: 1, what: 'snooze alarm', daysAgo: 26),
        mk(id: 2, what: 'snooze alarm', daysAgo: 23),
        mk(id: 3, what: 'snooze alarm', daysAgo: 20),
        mk(id: 4, what: 'snooze alarm', daysAgo: 17),
        mk(id: 5, what: 'snooze alarm', daysAgo: 14),
      ]);
      final imp = insights
          .where((i) => i.kind == InsightKind.improvement)
          .toList();
      expect(imp, hasLength(1));
      expect(imp.first.title, contains('14'));
      expect(imp.first.title.toLowerCase(), contains('snooze alarm'));
    });

    test('still-frequent `what` does not emit improvement', () async {
      // 5 entries with last one 2 days ago. daysSince < 7 → no streak.
      final insights = await engine().analyze([
        mk(id: 1, what: 'x', daysAgo: 14),
        mk(id: 2, what: 'x', daysAgo: 11),
        mk(id: 3, what: 'x', daysAgo: 8),
        mk(id: 4, what: 'x', daysAgo: 5),
        mk(id: 5, what: 'x', daysAgo: 2),
      ]);
      expect(
          insights.where((i) => i.kind == InsightKind.improvement), isEmpty);
    });

    test('quiet stretch <2x usual gap does not emit improvement', () async {
      // Last 8 days ago, avg gap 6d → 8 < 12 → no streak.
      final insights = await engine().analyze([
        mk(id: 1, what: 'y', daysAgo: 26),
        mk(id: 2, what: 'y', daysAgo: 20),
        mk(id: 3, what: 'y', daysAgo: 14),
        mk(id: 4, what: 'y', daysAgo: 8),
      ]);
      expect(
          insights.where((i) => i.kind == InsightKind.improvement), isEmpty);
    });

    test('streak rule sees beyond the 30d analyze window', () async {
      // All entries 40-50 days ago, last one 35 days ago. Should still emit
      // since streak uses the extended 60d window.
      final insights = await engine().analyze([
        mk(id: 1, what: 'old habit', daysAgo: 55),
        mk(id: 2, what: 'old habit', daysAgo: 50),
        mk(id: 3, what: 'old habit', daysAgo: 45),
        mk(id: 4, what: 'old habit', daysAgo: 40),
      ]);
      expect(
          insights.where((i) => i.kind == InsightKind.improvement),
          hasLength(1));
    });
  });

  group('RuleEngine — forecast', () {
    test('returns a forecast per strong (what, weekday, hour) triple',
        () async {
      // 3 Mondays at 7 AM, all in the 30d window. Within UTC+4 (Asia/Dubai),
      // these local datetimes are Mondays too, so the forecast triple groups.
      final forecasts = engine().forecast([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 7)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 11, 7)),
        mk(id: 3, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 18, 7)),
      ]);
      expect(forecasts, isNotEmpty);
      final f = forecasts.first;
      expect(f.kind, ForecastKind.weekdayHour);
      expect(f.what.toLowerCase(), contains('missed workout'));
      expect(f.basis, 3);
      // nextAt must be strictly in the future relative to fixedNow.
      expect(f.nextAt.isAfter(fixedNow), isTrue);
    });

    test('weak (<3) triples are dropped', () async {
      final forecasts = engine().forecast([
        mk(id: 1, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 4, 7)),
        mk(id: 2, what: 'missed workout',
            occurredAt: DateTime(2026, 5, 11, 7)),
      ]);
      expect(forecasts, isEmpty);
    });

    test('forecasts are sorted soonest first', () async {
      // Two strong triples: Mondays 7 AM and Tuesdays 9 PM. From fixedNow
      // (Sun May 24), the next Monday 7 AM (~next day) comes before the
      // next Tuesday 9 PM.
      final forecasts = engine().forecast([
        mk(id: 1, what: 'mon thing',
            occurredAt: DateTime(2026, 5, 4, 7)),
        mk(id: 2, what: 'mon thing',
            occurredAt: DateTime(2026, 5, 11, 7)),
        mk(id: 3, what: 'mon thing',
            occurredAt: DateTime(2026, 5, 18, 7)),
        mk(id: 4, what: 'tue thing',
            occurredAt: DateTime(2026, 5, 5, 21)),
        mk(id: 5, what: 'tue thing',
            occurredAt: DateTime(2026, 5, 12, 21)),
        mk(id: 6, what: 'tue thing',
            occurredAt: DateTime(2026, 5, 19, 21)),
      ]);
      expect(forecasts, hasLength(2));
      expect(
          forecasts.first.nextAt.isBefore(forecasts.last.nextAt), isTrue);
    });
  });

  group('RuleEngine — semantic grouping', () {
    test(
        'fuzzy `what` synonyms (missed gym + skipped workout) merge into '
        'one pattern', () async {
      // 3 entries on Mondays at 7 AM phrased two different ways. With
      // exact-string matching this would be 1 "missed gym" + 2 "skipped
      // workout" (no pattern), but the semantic layer should merge them
      // into a single weekday/hour pattern.
      final insights = await engine().analyze([
        mk(id: 1, what: 'missed gym',
            occurredAt: DateTime(2026, 5, 4, 7)),
        mk(id: 2, what: 'skipped workout',
            occurredAt: DateTime(2026, 5, 11, 7)),
        mk(id: 3, what: 'skipped workout',
            occurredAt: DateTime(2026, 5, 18, 7)),
      ]);
      final patterns = insights
          .where((i) =>
              i.kind == InsightKind.pattern && i.title.contains('Monday'))
          .toList();
      expect(patterns, hasLength(1));
      expect(patterns.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });

    test('cause synonyms merge (tired + exhausted)', () async {
      final insights = await engine().analyze([
        mk(id: 1, what: 'a', cause: 'tired', daysAgo: 1),
        mk(id: 2, what: 'b', cause: 'exhausted', daysAgo: 4),
        mk(id: 3, what: 'c', cause: 'tired', daysAgo: 8),
      ]);
      final recurring = insights
          .where((i) =>
              i.kind == InsightKind.pattern && i.title.contains('keeps'))
          .toList();
      expect(recurring, hasLength(1));
      expect(recurring.first.evidenceIds, unorderedEquals([1, 2, 3]));
    });
  });

  group('RuleEngine — multi-step chain', () {
    test('3 A->B->C cascades within window fire one cascade insight',
        () async {
      // Three nightly cascades: argument → bad sleep → missed workout.
      // Gaps: 3h then 5h, both within multiStepWindowHours.
      final insights = await engine().analyze([
        mk(id: 1, what: 'argument',
            occurredAt: DateTime(2026, 5, 18, 20)),
        mk(id: 2, what: "couldn't sleep",
            occurredAt: DateTime(2026, 5, 18, 23)),
        mk(id: 3, what: 'missed run',
            occurredAt: DateTime(2026, 5, 19, 4)),
        mk(id: 4, what: 'argument',
            occurredAt: DateTime(2026, 5, 19, 20)),
        mk(id: 5, what: "couldn't sleep",
            occurredAt: DateTime(2026, 5, 19, 23)),
        mk(id: 6, what: 'missed run',
            occurredAt: DateTime(2026, 5, 20, 4)),
        mk(id: 7, what: 'argument',
            occurredAt: DateTime(2026, 5, 20, 20)),
        mk(id: 8, what: "couldn't sleep",
            occurredAt: DateTime(2026, 5, 20, 23)),
        mk(id: 9, what: 'missed run',
            occurredAt: DateTime(2026, 5, 21, 4)),
      ]);
      final cascades = insights
          .where((i) =>
              i.kind == InsightKind.chain &&
              i.title.contains('→') &&
              i.title.contains('argument'))
          .toList();
      expect(cascades, hasLength(1));
      expect(cascades.first.evidenceIds.length, greaterThanOrEqualTo(9));
    });

    test('cascade with same-concept B and C is skipped', () async {
      // Middle and end both "missed workout" → only the depth-2 chain fires,
      // not a depth-3 with two same-concept steps.
      final insights = await engine().analyze([
        for (var i = 0; i < 3; i++) ...[
          mk(id: i * 3 + 1, what: 'argument',
              occurredAt: DateTime(2026, 5, 18 + i, 20)),
          mk(id: i * 3 + 2, what: 'missed workout',
              occurredAt: DateTime(2026, 5, 18 + i, 23)),
          mk(id: i * 3 + 3, what: 'missed workout',
              occurredAt: DateTime(2026, 5, 19 + i, 4)),
        ],
      ]);
      expect(
          insights.where((i) =>
              i.kind == InsightKind.chain &&
              i.title.contains('→') &&
              i.title.split('→').length == 3),
          isEmpty);
    });
  });

  group('RuleEngine — anomaly week', () {
    test('last 7d notably worse than the prior 4 weeks emits anomaly',
        () async {
      // 6 entries this week, 1 in each of the 4 prior weeks (avg 1/wk).
      // 6 / 1 = 6.0x, well over the 2x threshold.
      final insights = await engine().analyze([
        // Prior 4 weeks: 1 entry each
        mk(id: 1, what: 'a', daysAgo: 10),
        mk(id: 2, what: 'a', daysAgo: 17),
        mk(id: 3, what: 'a', daysAgo: 24),
        mk(id: 4, what: 'a', daysAgo: 30),
        // This week: 6 entries
        for (var i = 5; i < 11; i++)
          mk(id: i, what: 'a', daysAgo: 1),
      ]);
      expect(
          insights.where((i) => i.title.toLowerCase().contains('worse than')),
          hasLength(1));
    });

    test('no anomaly when this week is in line with prior weeks', () async {
      final insights = await engine().analyze([
        for (var i = 1; i <= 8; i++) mk(id: i, what: 'a', daysAgo: i * 4),
      ]);
      expect(
          insights.where((i) => i.title.toLowerCase().contains('worse than')),
          isEmpty);
    });
  });

  group('RuleEngine — narrative', () {
    test('returns null when no entries in the last 7 days', () {
      final n = engine().narrative([
        mk(id: 1, what: 'x', daysAgo: 30),
      ]);
      expect(n, isNull);
    });

    test('mentions count, dominant what, and total cost', () {
      final n = engine().narrative([
        mk(id: 1, what: 'missed gym', daysAgo: 1, costMinutes: 30),
        mk(id: 2, what: 'skipped workout', daysAgo: 2, costMinutes: 30),
        mk(id: 3, what: 'something else',
            daysAgo: 3, costMoney: 50),
      ]);
      expect(n, isNotNull);
      expect(n!, contains('3'));
      expect(n.toLowerCase(), contains('week'));
      // The dominant cluster (missed gym + skipped workout via semantic)
      // should be quoted.
      expect(n, contains('"missed gym"'));
    });
  });

  group('RuleEngine — RAG suggestion fallback', () {
    test('borrows a solution from a semantically similar past entry',
        () async {
      // Three "skipped workout" entries forming a Tuesday-weekday pattern.
      // No solutions on any of them. A separate "missed gym" entry sits on
      // a Sunday with a solution — same concept key but different weekday,
      // so it does NOT join the Tuesday group. The RAG fallback should
      // surface its solution prefixed with `From "missed gym":`.
      final allEntries = [
        mk(id: 1, what: 'skipped workout',
            occurredAt: DateTime(2026, 5, 5, 7)),
        mk(id: 2, what: 'skipped workout',
            occurredAt: DateTime(2026, 5, 12, 7)),
        mk(id: 3, what: 'skipped workout',
            occurredAt: DateTime(2026, 5, 19, 7)),
        mk(
            id: 99,
            what: 'missed gym',
            solution: 'lay out clothes the night before',
            occurredAt: DateTime(2026, 5, 17, 7)),
      ];
      final insights = await engine().analyze(allEntries);
      final p = insights.firstWhere((i) =>
          i.kind == InsightKind.pattern &&
          i.title.contains('Tuesday'));
      expect(p.suggestion, isNotNull);
      expect(p.suggestion!, startsWith('From "missed gym":'));
      expect(p.suggestion!, contains('lay out clothes'));
    });
  });
}
