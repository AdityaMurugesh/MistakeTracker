// Owner: Insights
// v1 implementation of SuggestionEngine. Pure Dart, no DB access.
//
// Rule families:
//   1. Recurring cause       — same cause appearing >=3 times in window
//   2. Time-of-day pattern   — (what, weekday) and (what, hour) buckets >=3
//   3. Chain detection       — (A.what -> B.what) within 6h, >=3 times
//   4. Cross-cause chain     — (a.cause -> b.what) within 24h, >=3 times
//   5. Multi-step chain      — A -> B -> C cascade >=3 times
//   6. Cost aggregation      — sum costMinutes / costMoney + yearly projection
//   7. Streak / improvement  — `what` quiet for notably longer than usual
//   8. Anomaly week          — last 7d notably worse than the prior 4 weeks
//
// All grouping keys go through a Semantic layer so "missed gym" and
// "skipped workout" merge into one pattern instead of staying split.
// Suggestions fall back to RAG-style retrieval over the user's other
// semantically-similar entries when there's no in-group past solution.
//
// Forecasts (forward-looking projections) live in a separate method,
// RuleEngine.forecast(entries), since they don't fit the SuggestionEngine
// contract.
//
// All thresholds are constants below — tweak in one place.

import 'narrative_engine.dart';
import 'outlook_engine.dart';
import 'semantic.dart';
import 'suggestion_engine.dart';
import 'models/entry.dart';
import 'models/forecast.dart';
import 'models/insight.dart';

class RuleEngine implements SuggestionEngine, NarrativeEngine, OutlookEngine {
  // Tweakable thresholds
  static const int minOccurrencesForPattern = 3;
  static const int lookbackDays = 30;
  static const int chainWindowHours = 6;
  static const int crossCauseWindowHours = 24;
  static const int streakLookbackDays = 60;
  static const int streakMinDaysSince = 7;
  static const int multiStepWindowHours = 24;
  static const int anomalyPriorWeeks = 4;
  static const double anomalyMultiplier = 2.0;
  static const double ragMinSimilarity = 0.45;

  /// Injected "now" for tests; defaults to DateTime.now().
  final DateTime Function() _now;
  final Semantic _semantic;

  RuleEngine({DateTime Function()? now, Semantic? semantic})
      : _now = (now ?? DateTime.now),
        _semantic = semantic ?? const Semantic();

  @override
  Future<List<Insight>> analyze(List<Entry> entries) async {
    final insights = <Insight>[];

    final now = _now();
    final windowStart = now.subtract(const Duration(days: lookbackDays));
    final inWindow = entries
        .where((e) => !e.occurredAt.isBefore(windowStart))
        .toList(growable: false);

    insights.addAll(_anomalyWeek(entries));
    insights.addAll(_recurringCause(inWindow, entries));
    insights.addAll(_weekdayPattern(inWindow, entries));
    insights.addAll(_hourPattern(inWindow, entries));
    insights.addAll(_chainDetection(inWindow, entries));
    insights.addAll(_multiStepChain(inWindow));
    insights.addAll(_crossCauseChain(inWindow));
    insights.addAll(_costInsight(inWindow));
    insights.addAll(_streakInsight(entries)); // uses extended window

    return insights;
  }

  /// Composes a short narrative summary of the user's last 7 days, suitable
  /// for a hero card at the top of the Insights screen. Reads from the same
  /// data the rules use; the wording is templated, not generated.
  @override
  Future<String?> narrative(List<Entry> entries) async {
    final now = _now();
    final weekStart = now.subtract(const Duration(days: 7));
    final week = entries
        .where((e) => !e.occurredAt.isBefore(weekStart))
        .toList(growable: false);
    if (week.isEmpty) return null;

    // Dominant concept this week.
    final byConcept = <String, List<Entry>>{};
    for (final e in week) {
      final k = _semantic.conceptKey(e.what);
      if (k == null) continue;
      (byConcept[k] ??= []).add(e);
    }
    final ranked = byConcept.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    final parts = <String>[];
    parts.add(
        'You logged ${week.length} failure${week.length == 1 ? '' : 's'} this week.');

    if (ranked.isNotEmpty && ranked.first.value.length >= 2) {
      final dominantWhat = ranked.first.value.first.what.trim();
      parts.add(
          '"$dominantWhat" was the loudest signal (${ranked.first.value.length}x).');
    }

    var totalMoney = 0;
    var totalMinutes = 0;
    for (final e in week) {
      totalMoney += e.costMoney ?? 0;
      totalMinutes += e.costMinutes ?? 0;
    }
    if (totalMoney > 0 || totalMinutes > 0) {
      final costParts = <String>[];
      if (totalMoney > 0) costParts.add('\$$totalMoney');
      if (totalMinutes > 0) costParts.add('$totalMinutes min');
      parts.add('Cost so far: ${costParts.join(' + ')}.');
    }

    return parts.join(' ');
  }

  /// Rule engine has no forward-looking prose — the Coming Up panel
  /// already renders the structured forecasts. The outlook card is an
  /// AI-only feature; here it returns null so the card stays hidden when
  /// AI is off (and as a graceful fallback if the LLM call fails).
  @override
  Future<String?> outlook(List<Entry> entries, List<Forecast> forecasts) async =>
      null;

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
      final what = _semantic.conceptKey(e.what);
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
  // Group entries by the cause's concept key (so "Tired" / "exhausted" /
  // "sleepy" merge into one). For any cluster with >= threshold occurrences,
  // emit a pattern Insight; suggestion = user's past solution for the same
  // cause if any, else a RAG-style borrow from a semantically similar entry.
  Iterable<Insight> _recurringCause(
    List<Entry> entries,
    List<Entry> allEntries,
  ) sync* {
    final byCause = <String, List<Entry>>{};
    for (final e in entries) {
      final key = _semantic.conceptKey(e.cause);
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
        suggestion: _suggestionFor(
          group: group,
          allEntries: allEntries,
          queryOverride: group.first.cause,
        ),
      );
    }
  }

  // Rule 2a: weekday pattern.
  // (what conceptKey, weekday) pairs with >= threshold occurrences.
  Iterable<Insight> _weekdayPattern(
    List<Entry> entries,
    List<Entry> allEntries,
  ) sync* {
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final what = _semantic.conceptKey(e.what);
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
        suggestion: _suggestionFor(group: group, allEntries: allEntries),
      );
    }
  }

  // Rule 2b: hour-of-day pattern.
  // (what conceptKey, local hour) pairs with >= threshold occurrences.
  Iterable<Insight> _hourPattern(
    List<Entry> entries,
    List<Entry> allEntries,
  ) sync* {
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final what = _semantic.conceptKey(e.what);
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
        suggestion: _suggestionFor(group: group, allEntries: allEntries),
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
  Iterable<Insight> _chainDetection(
    List<Entry> entries,
    List<Entry> allEntries,
  ) sync* {
    if (entries.length < 2) return;
    final sorted = [...entries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    const window = Duration(hours: chainWindowHours);

    final pairs = <String, List<List<Entry>>>{};
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (b.occurredAt.difference(a.occurredAt) > window) continue;
      final aWhat = _semantic.conceptKey(a.what);
      final bWhat = _semantic.conceptKey(b.what);
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

      // Suggestion: solution from the A side (the trigger), since that's
      // where the user would intervene to break the chain.
      final aEntries = [for (final p in occurrences) p[0]];

      yield Insight(
        kind: InsightKind.chain,
        title: '"$aDisplay" often leads to "$bDisplay"',
        body:
            '${occurrences.length} times in the last $lookbackDays days, '
            'within $chainWindowHours hours.',
        evidenceIds: ids,
        suggestion: _suggestionFor(group: aEntries, allEntries: allEntries),
      );
    }
  }

  // Rule 5: multi-step chain (A -> B -> C).
  // Walks the chronological entry list and counts every triple
  // (entry[i], entry[i+1], entry[i+2]) where:
  //   • each successive gap is within multiStepWindowHours
  //   • all three concept-keys are distinct
  // Triples with >= threshold occurrences become a cascade insight.
  Iterable<Insight> _multiStepChain(List<Entry> entries) sync* {
    if (entries.length < 3) return;
    final sorted = [...entries]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    const window = Duration(hours: multiStepWindowHours);

    final triples = <String, List<List<Entry>>>{};
    for (var i = 0; i < sorted.length - 2; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final c = sorted[i + 2];
      if (b.occurredAt.difference(a.occurredAt) > window) continue;
      if (c.occurredAt.difference(b.occurredAt) > window) continue;
      final ka = _semantic.conceptKey(a.what);
      final kb = _semantic.conceptKey(b.what);
      final kc = _semantic.conceptKey(c.what);
      if (ka == null || kb == null || kc == null) continue;
      if (ka == kb || kb == kc || ka == kc) continue;
      (triples['$ka|$kb|$kc'] ??= []).add([a, b, c]);
    }

    for (final key in _sortKeysByCountDesc(triples)) {
      final occurrences = triples[key]!;
      if (occurrences.length < minOccurrencesForPattern) continue;

      final aDisplay = occurrences.first[0].what.trim();
      final bDisplay = occurrences.first[1].what.trim();
      final cDisplay = occurrences.first[2].what.trim();

      final idSet = <int>{};
      for (final triple in occurrences) {
        for (final e in triple) {
          if (e.id != null) idSet.add(e.id!);
        }
      }

      yield Insight(
        kind: InsightKind.chain,
        title: '"$aDisplay" → "$bDisplay" → "$cDisplay"',
        body:
            'This 3-step cascade fired ${occurrences.length} times. '
            'Stopping it early breaks the whole chain.',
        evidenceIds: idSet.toList()..sort(),
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
      final aCause = _semantic.conceptKey(a.cause);
      final aWhat = _semantic.conceptKey(a.what);
      final bWhat = _semantic.conceptKey(b.what);
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
      final w = _semantic.conceptKey(e.what);
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

  // Rule 8: anomaly week.
  // Compares the last 7 days' failure count to the average count per week
  // over the prior anomalyPriorWeeks. If notably worse (>= anomalyMultiplier
  // and at least 3 events), surface as a pattern insight at the top.
  Iterable<Insight> _anomalyWeek(List<Entry> entries) sync* {
    final now = _now();
    final lastWeekStart = now.subtract(const Duration(days: 7));
    final priorStart =
        now.subtract(const Duration(days: 7 * (anomalyPriorWeeks + 1)));

    final lastWeek = <Entry>[];
    final priorPeriod = <Entry>[];
    for (final e in entries) {
      if (!e.occurredAt.isBefore(lastWeekStart)) {
        lastWeek.add(e);
      } else if (e.occurredAt.isAfter(priorStart)) {
        priorPeriod.add(e);
      }
    }
    if (lastWeek.length < 3) return;
    if (priorPeriod.isEmpty) return;

    final avgPriorPerWeek = priorPeriod.length / anomalyPriorWeeks;
    if (avgPriorPerWeek < 1) return;

    final ratio = lastWeek.length / avgPriorPerWeek;
    if (ratio < anomalyMultiplier) return;

    yield Insight(
      kind: InsightKind.pattern,
      title:
          'This week is ${ratio.toStringAsFixed(1)}x worse than usual',
      body:
          'You logged ${lastWeek.length} failures this week vs '
          '${avgPriorPerWeek.toStringAsFixed(1)} avg over the prior '
          '$anomalyPriorWeeks weeks.',
      evidenceIds: [for (final e in lastWeek) if (e.id != null) e.id!],
    );
  }

  // --- helpers ---

  List<int> _idsOf(List<Entry> entries) =>
      [for (final e in entries) if (e.id != null) e.id!];

  /// Suggestion text for an insight.
  ///
  /// 1. Direct: most recent non-empty solution from inside the group.
  /// 2. RAG: if no in-group solution, retrieve the user's other entries by
  ///    similarity to the group's representative text, and surface the top
  ///    similar entry's solution. Labeled with "From \"$what\":" so the user
  ///    can tell when a suggestion is borrowed from a related-but-different
  ///    entry rather than being theirs verbatim.
  String? _suggestionFor({
    required List<Entry> group,
    required List<Entry> allEntries,
    String? queryOverride,
  }) {
    final newest = [...group]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    for (final e in newest) {
      final s = e.solution?.trim();
      if (s != null && s.isNotEmpty) return s;
    }

    final query = queryOverride ?? group.first.what;
    final inGroupIds = {for (final g in group) if (g.id != null) g.id!};
    final ranked = <(double, Entry)>[];
    for (final e in allEntries) {
      if (e.id != null && inGroupIds.contains(e.id)) continue;
      final sol = e.solution?.trim();
      if (sol == null || sol.isEmpty) continue;
      final sim = _semantic.similarity(query, e.what);
      if (sim >= ragMinSimilarity) ranked.add((sim, e));
    }
    if (ranked.isEmpty) return null;
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    final top = ranked.first.$2;
    return 'From "${top.what.trim()}": ${top.solution!.trim()}';
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
