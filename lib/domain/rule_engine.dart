// Owner: Insights
// v1 implementation of SuggestionEngine. Pure Dart, no DB access.
//
// Three rule families to implement:
//   1. Recurring cause   — group by `cause`, surface causes appearing in >=3 entries
//   2. Time-of-day pattern — group by (what, day_of_week) or (what, hour); flag >=3 in 30d
//   3. Chain detection   — for each entry, look at next entry within N hours;
//                          surface (A -> B) pairs that appear >=3 times
//
// Plus: suggestion text = user's own past `solution` for the same `what`, if any.
//
// All thresholds are constants below — tweak in one place.

import 'suggestion_engine.dart';
import 'models/entry.dart';
import 'models/insight.dart';

class RuleEngine implements SuggestionEngine {
  // Tweakable thresholds
  static const int minOccurrencesForPattern = 3;
  static const int lookbackDays = 30;
  static const int chainWindowHours = 6;

  /// Injected "now" for tests; defaults to DateTime.now().
  final DateTime Function() _now;

  RuleEngine({DateTime Function()? now}) : _now = (now ?? DateTime.now);

  @override
  Future<List<Insight>> analyze(List<Entry> entries) async {
    final insights = <Insight>[];

    final now = _now();
    final windowStart = now.subtract(const Duration(days: lookbackDays));
    final inWindow = entries
        .where((e) => !e.occurredAt.isBefore(windowStart))
        .toList(growable: false);

    insights.addAll(_recurringCause(inWindow));
    insights.addAll(_costInsight(inWindow));
    // TODO: rule 2 — time-of-day pattern
    // TODO: rule 3 — chain detection
    // TODO: improvement trend insight

    return insights;
  }

  // Rule 1: recurring cause.
  // Group entries by normalized cause; for any cause with >= threshold occurrences,
  // emit a pattern Insight whose suggestion is the user's own past `solution`
  // (most recent non-empty) for the same cause, if any.
  Iterable<Insight> _recurringCause(List<Entry> entries) sync* {
    final byCause = <String, List<Entry>>{};
    for (final e in entries) {
      final key = _normalizeCause(e.cause);
      if (key == null) continue;
      (byCause[key] ??= []).add(e);
    }

    // Stable output: iterate causes in descending count, then alphabetical.
    final causes = byCause.keys.toList()
      ..sort((a, b) {
        final ca = byCause[a]!.length;
        final cb = byCause[b]!.length;
        if (cb != ca) return cb.compareTo(ca);
        return a.compareTo(b);
      });

    for (final cause in causes) {
      final group = byCause[cause]!;
      if (group.length < minOccurrencesForPattern) continue;

      group.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      final displayCause = group.first.cause!.trim();
      final evidenceIds = <int>[
        for (final e in group)
          if (e.id != null) e.id!,
      ];

      final suggestion = _firstSolution(group);

      yield Insight(
        kind: InsightKind.pattern,
        title: '"$displayCause" keeps coming up',
        body:
            '${group.length} entries in the last $lookbackDays days share this cause.',
        evidenceIds: evidenceIds,
        suggestion: suggestion,
      );
    }
  }

  // Cost insight: sum costMinutes and costMoney within the lookback window.
  Iterable<Insight> _costInsight(List<Entry> entries) sync* {
    var minutes = 0;
    var money = 0;
    final ids = <int>[];
    for (final e in entries) {
      final m = e.costMinutes ?? 0;
      final c = e.costMoney ?? 0;
      if (m == 0 && c == 0) continue;
      minutes += m;
      money += c;
      if (e.id != null) ids.add(e.id!);
    }
    if (minutes == 0 && money == 0) return;

    final parts = <String>[];
    if (money > 0) parts.add('about $money in money');
    if (minutes > 0) parts.add('$minutes minutes of your time');

    yield Insight(
      kind: InsightKind.cost,
      title: 'Cost of failures, last $lookbackDays days',
      body: 'These entries cost ${parts.join(' and ')}.',
      evidenceIds: ids,
    );
  }

  String? _normalizeCause(String? cause) {
    if (cause == null) return null;
    final trimmed = cause.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _firstSolution(List<Entry> entriesNewestFirst) {
    for (final e in entriesNewestFirst) {
      final s = e.solution?.trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }
}
