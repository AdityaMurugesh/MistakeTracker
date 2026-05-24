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
    insights.addAll(_weekdayPattern(inWindow));
    insights.addAll(_hourPattern(inWindow));
    insights.addAll(_costInsight(inWindow));
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
      final key = _normalize(e.cause);
      if (key == null) continue;
      (byCause[key] ??= []).add(e);
    }

    final causes = _sortKeysByCountDesc(byCause);
    for (final cause in causes) {
      final group = byCause[cause]!;
      if (group.length < minOccurrencesForPattern) continue;

      group.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

      yield Insight(
        kind: InsightKind.pattern,
        title: '"${group.first.cause!.trim()}" keeps coming up',
        body:
            '${group.length} entries in the last $lookbackDays days share this cause.',
        evidenceIds: _idsOf(group),
        suggestion: _firstSolution(group),
      );
    }
  }

  // Rule 2a: weekday pattern.
  // For each (normalized what, weekday) pair, emit a pattern Insight when
  // count >= threshold. E.g. "'missed workout' on Mondays — 3 in the last 30d".
  Iterable<Insight> _weekdayPattern(List<Entry> entries) sync* {
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final what = _normalize(e.what);
      if (what == null) continue;
      final wd = e.occurredAt.toLocal().weekday;
      (groups['$what|$wd'] ??= []).add(e);
    }

    for (final key in _sortKeysByCountDesc(groups)) {
      final group = groups[key]!;
      if (group.length < minOccurrencesForPattern) continue;

      group.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final displayWhat = group.first.what.trim();
      final wdName = _weekdayName(group.first.occurredAt.toLocal().weekday);

      yield Insight(
        kind: InsightKind.pattern,
        title: '"$displayWhat" tends to happen on ${wdName}s',
        body:
            '${group.length} of these landed on a $wdName in the last $lookbackDays days.',
        evidenceIds: _idsOf(group),
        suggestion: _firstSolution(group),
      );
    }
  }

  // Rule 2b: hour-of-day pattern.
  // For each (normalized what, local hour) pair, emit a pattern Insight when
  // count >= threshold.
  Iterable<Insight> _hourPattern(List<Entry> entries) sync* {
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final what = _normalize(e.what);
      if (what == null) continue;
      final hour = e.occurredAt.toLocal().hour;
      (groups['$what|$hour'] ??= []).add(e);
    }

    for (final key in _sortKeysByCountDesc(groups)) {
      final group = groups[key]!;
      if (group.length < minOccurrencesForPattern) continue;

      group.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final displayWhat = group.first.what.trim();
      final hourLabel =
          _formatHour(group.first.occurredAt.toLocal().hour);

      yield Insight(
        kind: InsightKind.pattern,
        title: '"$displayWhat" tends to happen around $hourLabel',
        body:
            '${group.length} of these happened around $hourLabel in the last $lookbackDays days.',
        evidenceIds: _idsOf(group),
        suggestion: _firstSolution(group),
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

  // --- helpers ---

  String? _normalize(String? s) {
    if (s == null) return null;
    final t = s.trim().toLowerCase();
    return t.isEmpty ? null : t;
  }

  List<int> _idsOf(List<Entry> entries) =>
      [for (final e in entries) if (e.id != null) e.id!];

  String? _firstSolution(List<Entry> entriesNewestFirst) {
    for (final e in entriesNewestFirst) {
      final s = e.solution?.trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  // Stable ordering: descending count, then alphabetical key.
  List<String> _sortKeysByCountDesc(Map<String, List<Entry>> groups) {
    final keys = groups.keys.toList();
    keys.sort((a, b) {
      final cmp = groups[b]!.length.compareTo(groups[a]!.length);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    return keys;
  }

  String _weekdayName(int wd) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[wd - 1];
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour == 12) return '12 PM';
    if (hour < 12) return '$hour AM';
    return '${hour - 12} PM';
  }
}
