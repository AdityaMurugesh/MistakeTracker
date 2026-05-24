// Owner: Insights
// v1 implementation of SuggestionEngine. Pure Dart, no DB access.
//
// Rule families:
//   1. Recurring cause       — same cause appearing >=3 times in window
//   2. Time-of-day pattern   — (what, weekday) and (what, hour) buckets >=3
//   3. Chain detection       — (A.what -> B.what) within 6h, >=3 times
//   4. Cross-cause chain     — (a.cause -> b.what) within 24h, >=3 times
//   5. Cost aggregation      — sum costMinutes / costMoney + yearly projection
//   6. Streak / improvement  — `what` quiet for notably longer than usual
//
// Forecasts (forward-looking projections) live in a separate method,
// RuleEngine.forecast(entries), since they don't fit the SuggestionEngine
// contract.
//
// Plus: suggestion text = user's own past `solution` for the same `what`, if any.
//
// All thresholds are constants below — tweak in one place.

import 'suggestion_engine.dart';
import 'models/entry.dart';
import 'models/forecast.dart';
import 'models/insight.dart';

class RuleEngine implements SuggestionEngine {
  // Tweakable thresholds
  static const int minOccurrencesForPattern = 3;
  static const int lookbackDays = 30;
  static const int chainWindowHours = 6;
  static const int crossCauseWindowHours = 24;
  static const int streakLookbackDays = 60;
  static const int streakMinDaysSince = 7;

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
    insights.addAll(_chainDetection(inWindow));
    insights.addAll(_crossCauseChain(inWindow));
    insights.addAll(_costInsight(inWindow));
    insights.addAll(_streakInsight(entries)); // uses extended window

    return insights;
  }

  /// Forward-looking: projects the next likely occurrence of each strong
  /// (what, weekday, hour) pattern. Returned sorted by soonest first.
  List<Forecast> forecast(List<Entry> entries) {
    final now = _now();
    final windowStart = now.subtract(const Duration(days: lookbackDays));
    final inWindow = entries
        .where((e) => !e.occurredAt.isBefore(windowStart))
        .toList(growable: false);

    final triples = <String, List<Entry>>{};
    for (final e in inWindow) {
      final what = _normalize(e.what);
      if (what == null) continue;
      final local = e.occurredAt.toLocal();
      (triples['$what|${local.weekday}|${local.hour}'] ??= []).add(e);
    }

    final out = <Forecast>[];
    for (final group in triples.values) {
      if (group.length < minOccurrencesForPattern) continue;
      final last = group.last;
      final local = last.occurredAt.toLocal();
      final next = _nextLocalOccurrence(now.toLocal(), local.weekday, local.hour);
      out.add(Forecast(
        kind: ForecastKind.weekdayHour,
        what: last.what.trim(),
        nextAt: next.toUtc(),
        basis: group.length,
        basisLabel:
            '${_weekdayName(local.weekday)}s at ${_formatHour(local.hour)}',
      ));
    }
    out.sort((a, b) => a.nextAt.compareTo(b.nextAt));
    return out;
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

  // Rule 3: chain detection.
  // For each entry A, look at the immediately next chronological entry B.
  // If B falls within chainWindowHours of A and has a different `what`, count
  // the (A.what -> B.what) pair. Surface pairs with >= threshold occurrences.
  //
  // Same-`what` consecutive entries are skipped here — they're already
  // covered by the recurring-cause / weekday / hour rules and would just be
  // noise as "X often leads to X".
  Iterable<Insight> _chainDetection(List<Entry> entries) sync* {
    if (entries.length < 2) return;
    final sorted = [...entries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    const window = Duration(hours: chainWindowHours);

    final pairs = <String, List<List<Entry>>>{};
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (b.occurredAt.difference(a.occurredAt) > window) continue;
      final aWhat = _normalize(a.what);
      final bWhat = _normalize(b.what);
      if (aWhat == null || bWhat == null) continue;
      if (aWhat == bWhat) continue;
      (pairs['$aWhat|$bWhat'] ??= []).add([a, b]);
    }

    for (final key in _sortKeysByCountDesc(pairs)) {
      final occurrences = pairs[key]!;
      if (occurrences.length < minOccurrencesForPattern) continue;

      final aDisplay = occurrences.first[0].what.trim();
      final bDisplay = occurrences.first[1].what.trim();

      final idSet = <int>{};
      for (final pair in occurrences) {
        for (final e in pair) {
          if (e.id != null) idSet.add(e.id!);
        }
      }
      final ids = idSet.toList()..sort();

      // Suggestion: most recent solution from the A side (the trigger), since
      // that's where the user would intervene to break the chain.
      final aEntries = [for (final p in occurrences) p[0]]
        ..sort((x, y) => y.occurredAt.compareTo(x.occurredAt));

      yield Insight(
        kind: InsightKind.chain,
        title: '"$aDisplay" often leads to "$bDisplay"',
        body:
            '${occurrences.length} times in the last $lookbackDays days, '
            'within $chainWindowHours hours.',
        evidenceIds: ids,
        suggestion: _firstSolution(aEntries),
      );
    }
  }

  // Rule 4: cross-cause chain.
  // For each entry A with a non-empty cause, look at the immediately next
  // chronological entry B. If B falls within crossCauseWindowHours and has
  // a different `what` than A, count (A.cause -> B.what) and surface pairs
  // with >= threshold occurrences. Different from rule 3: it correlates the
  // *trigger reason* (cause) with the next failure (what), not what with what.
  Iterable<Insight> _crossCauseChain(List<Entry> entries) sync* {
    if (entries.length < 2) return;
    final sorted = [...entries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    const window = Duration(hours: crossCauseWindowHours);

    final pairs = <String, List<List<Entry>>>{};
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (b.occurredAt.difference(a.occurredAt) > window) continue;
      final aCause = _normalize(a.cause);
      final aWhat = _normalize(a.what);
      final bWhat = _normalize(b.what);
      if (aCause == null || aWhat == null || bWhat == null) continue;
      if (aWhat == bWhat) continue; // already covered by recurring rules
      (pairs['$aCause||$bWhat'] ??= []).add([a, b]);
    }

    for (final key in _sortKeysByCountDesc(pairs)) {
      final occurrences = pairs[key]!;
      if (occurrences.length < minOccurrencesForPattern) continue;

      final causeDisplay = occurrences.first[0].cause!.trim();
      final whatDisplay = occurrences.first[1].what.trim();

      final idSet = <int>{};
      for (final pair in occurrences) {
        for (final e in pair) {
          if (e.id != null) idSet.add(e.id!);
        }
      }

      yield Insight(
        kind: InsightKind.chain,
        title:
            'When the cause is "$causeDisplay", "$whatDisplay" often follows',
        body:
            '${occurrences.length} times in the last $lookbackDays days, '
            'within $crossCauseWindowHours hours.',
        evidenceIds: idSet.toList()..sort(),
      );
    }
  }

  // Cost insight: sum costMinutes and costMoney within the lookback window,
  // plus a yearly projection extrapolated linearly from the 30-day rate.
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

    final projParts = <String>[];
    if (money > 0) {
      final perYear = (money / lookbackDays * 365).round();
      projParts.add('\$$perYear');
    }
    if (minutes > 0) {
      final yearMinutes = (minutes / lookbackDays * 365).round();
      final yearHours = (yearMinutes / 60).round();
      projParts.add('$yearHours hours');
    }
    final projection = projParts.join(' and ');

    yield Insight(
      kind: InsightKind.cost,
      title: 'Cost of failures, last $lookbackDays days',
      body: 'These entries cost ${parts.join(' and ')}. At this rate, '
          "that's roughly $projection over a year.",
      evidenceIds: ids,
    );
  }

  // Streak / improvement insight.
  // For each `what` with >= 3 entries in the extended (60d) window, compute
  // days since the most recent occurrence and the average gap between
  // entries. If the user has gone notably longer than usual (>= 7 days and
  // >= 2x the average gap), surface that as an improvement.
  Iterable<Insight> _streakInsight(List<Entry> entries) sync* {
    final now = _now();
    final start = now.subtract(const Duration(days: streakLookbackDays));
    final filtered = entries.where((e) => !e.occurredAt.isBefore(start)).toList();

    final byWhat = <String, List<Entry>>{};
    for (final e in filtered) {
      final w = _normalize(e.what);
      if (w == null) continue;
      (byWhat[w] ??= []).add(e);
    }

    for (final group in byWhat.values) {
      if (group.length < minOccurrencesForPattern) continue;
      group.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

      final last = group.last.occurredAt;
      final daysSince = now.difference(last).inDays;
      if (daysSince < streakMinDaysSince) continue;

      var gapSum = 0;
      for (var i = 1; i < group.length; i++) {
        gapSum += group[i].occurredAt.difference(group[i - 1].occurredAt).inDays;
      }
      final avgGap = gapSum / (group.length - 1);
      if (avgGap > 0 && daysSince < avgGap * 2) continue;

      final displayWhat = group.last.what.trim();
      final avgGapText = avgGap >= 1
          ? '${avgGap.toStringAsFixed(0)} day${avgGap >= 2 ? 's' : ''}'
          : 'under a day';

      yield Insight(
        kind: InsightKind.improvement,
        title: '$daysSince days since "$displayWhat"',
        body:
            'Your usual gap is about $avgGapText. Whatever you changed is working.',
        evidenceIds: _idsOf(group),
      );
    }
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
  List<String> _sortKeysByCountDesc<T>(Map<String, List<T>> groups) {
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

  /// Next local DateTime strictly after `fromLocal` whose weekday + hour match.
  DateTime _nextLocalOccurrence(DateTime fromLocal, int weekday, int hour) {
    var d = DateTime(fromLocal.year, fromLocal.month, fromLocal.day, hour);
    while (d.weekday != weekday || !d.isAfter(fromLocal)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
