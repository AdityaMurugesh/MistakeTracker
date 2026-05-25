// Owner: Insights
// Renders the rule-engine output as cards, plus forward-looking forecasts,
// a heatmap of when failures cluster, and per-card sparklines.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/entry.dart';
import '../domain/models/forecast.dart';
import '../domain/models/insight.dart';
import '../state/providers.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final llmAsync = ref.watch(insightsProvider);
    final ruleAsync = ref.watch(ruleInsightsProvider);
    final entriesAsync = ref.watch(entriesStreamProvider);
    final aiEnabled = ref.watch(aiSettingsProvider).enabled;
    final scheme = Theme.of(context).colorScheme;

    final severityById = <int, int>{
      for (final e in entriesAsync.valueOrNull ?? const <Entry>[])
        if (e.id != null) e.id!: e.severity,
    };

    // Effective list: prefer the LLM output once it lands; until then fall
    // back to the rule-engine list so the screen renders in ~50ms instead of
    // sitting on a spinner for 15-30s. When AI is off, llmAsync and ruleAsync
    // resolve at the same time with the same data.
    final List<Insight>? effective =
        llmAsync.valueOrNull ?? ruleAsync.valueOrNull;
    final llmStillCooking =
        aiEnabled && llmAsync.isLoading && ruleAsync.hasValue;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(insightsProvider);
          ref.invalidate(ruleInsightsProvider);
          ref.invalidate(forecastsProvider);
          ref.invalidate(narrativeProvider);
          ref.invalidate(ruleNarrativeProvider);
          ref.invalidate(outlookProvider);
          await ref.read(insightsProvider.future);
          await ref.read(forecastsProvider.future);
          await ref.read(narrativeProvider.future);
          await ref.read(outlookProvider.future);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              backgroundColor: scheme.surface,
              surfaceTintColor: scheme.surfaceTint,
              title: Text(
                'Insights',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (effective == null)
              llmAsync.hasError
                  ? SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(message: llmAsync.error.toString()),
                    )
                  : const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
            else if (effective.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                sliver: SliverList.builder(
                  itemCount: _rankByImpact(effective, severityById).length + 6,
                  itemBuilder: (context, i) {
                    final ranked = _rankByImpact(effective, severityById);
                    if (i == 0) return const _NarrativeCard();
                    if (i == 1) {
                      return _AiCookingPill(visible: llmStillCooking);
                    }
                    if (i == 2) return _SummaryHeader(insights: ranked);
                    if (i == 3) return const _ComingUpPanel();
                    if (i == 4) return const _OutlookCard();
                    if (i == 5) return const _Heatmap();
                    final idx = i - 6;
                    final insight = ranked[idx];
                    return _AnimatedReveal(
                      delayMs: 40 * idx,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _InsightCard(
                          insight: insight,
                          isTopPriority: idx == 0,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Ranking ----------------------------------------------------------------

/// Sort insights by an impact score so the loudest one is on top. Kind sets
/// the broad band (cost > chain > pattern > improvement); inside a band, the
/// score is evidence count × mean severity, so 3 catastrophic entries can
/// outrank 6 mild ones. Stable for ties.
List<Insight> _rankByImpact(
  List<Insight> insights,
  Map<int, int> severityById,
) {
  int kindWeight(InsightKind k) {
    switch (k) {
      case InsightKind.cost:
        return 40;
      case InsightKind.chain:
        return 30;
      case InsightKind.pattern:
        return 20;
      case InsightKind.improvement:
        return 10;
    }
  }

  double scoreOf(Insight i) {
    final ids = i.evidenceIds;
    double meanSeverity = 3;
    if (ids.isNotEmpty) {
      var sum = 0;
      var n = 0;
      for (final id in ids) {
        final s = severityById[id];
        if (s != null) {
          sum += s;
          n++;
        }
      }
      if (n > 0) meanSeverity = sum / n;
    }
    return kindWeight(i.kind) + ids.length * meanSeverity;
  }

  final indexed = [
    for (var i = 0; i < insights.length; i++) (i, insights[i])
  ];
  indexed.sort((a, b) {
    final cmp = scoreOf(b.$2).compareTo(scoreOf(a.$2));
    if (cmp != 0) return cmp;
    return a.$1.compareTo(b.$1);
  });
  return [for (final t in indexed) t.$2];
}

// ---- Narrative card ---------------------------------------------------------

class _NarrativeCard extends ConsumerWidget {
  const _NarrativeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final llmAsync = ref.watch(narrativeProvider);
    final ruleAsync = ref.watch(ruleNarrativeProvider);
    final scheme = Theme.of(context).colorScheme;

    // Same instant-then-swap pattern: render rule narrative immediately,
    // swap to LLM narrative when it lands.
    final narrative = llmAsync.valueOrNull ?? ruleAsync.valueOrNull;
    final narrativeAsync = AsyncValue.data(narrative);

    return narrativeAsync.maybeWhen(
      data: (narrative) {
        if (narrative == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  scheme.primary.withValues(alpha: 0.78),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'THIS WEEK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white.withValues(alpha: 0.85),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  narrative,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ---- "Polishing with AI" pill ----------------------------------------------
//
// Tiny inline indicator that shows above the cards while the LLM is still
// generating its output. We render rule-engine cards immediately so the
// screen never blocks on a spinner; this pill signals that the LLM is in
// flight and the cards will be upgraded shortly.

class _AiCookingPill extends StatelessWidget {
  const _AiCookingPill({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.secondary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Polishing with AI…',
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Outlook card (LLM-only) ------------------------------------------------

class _OutlookCard extends ConsumerWidget {
  const _OutlookCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlookAsync = ref.watch(outlookProvider);
    final scheme = Theme.of(context).colorScheme;

    return outlookAsync.maybeWhen(
      data: (text) {
        if (text == null || text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.tertiaryContainer,
                  scheme.tertiaryContainer.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: scheme.tertiary.withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.tertiary.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.tertiary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'LOOKING AHEAD',
                        style: TextStyle(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: scheme.onTertiaryContainer.withValues(alpha: 0.7),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onTertiaryContainer,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ---- Summary header ---------------------------------------------------------

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <InsightKind, int>{};
    for (final i in insights) {
      counts[i.kind] = (counts[i.kind] ?? 0) + 1;
    }
    final total = insights.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$total ',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                ),
                TextSpan(
                  text: total == 1 ? 'pattern' : 'patterns',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'from the last 30 days',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in _kindOrder)
                if ((counts[kind] ?? 0) > 0)
                  _KindChip(kind: kind, count: counts[kind]!),
            ],
          ),
        ],
      ),
    );
  }

  static const _kindOrder = [
    InsightKind.pattern,
    InsightKind.chain,
    InsightKind.cost,
    InsightKind.improvement,
  ];
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind, required this.count});
  final InsightKind kind;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(kind, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(palette.icon, size: 14, color: palette.accent),
          const SizedBox(width: 6),
          Text(
            '$count ${_labelFor(kind).toLowerCase()}',
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Coming Up panel --------------------------------------------------------

class _ComingUpPanel extends ConsumerWidget {
  const _ComingUpPanel();

  static const _maxShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecastsAsync = ref.watch(forecastsProvider);
    return forecastsAsync.maybeWhen(
      data: (forecasts) {
        if (forecasts.isEmpty) return const SizedBox.shrink();
        final shown = forecasts.take(_maxShown).toList();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _ComingUpCard(forecasts: shown),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ComingUpCard extends StatelessWidget {
  const _ComingUpCard({required this.forecasts});
  final List<Forecast> forecasts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final containerTint = scheme.primaryContainer.withValues(alpha: 0.45);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            containerTint,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.schedule_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'COMING UP',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    'Your next at-risk windows',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < forecasts.length; i++) ...[
            _ForecastRow(forecast: forecasts[i]),
            if (i < forecasts.length - 1)
              Divider(
                height: 18,
                color: primary.withValues(alpha: 0.12),
              ),
          ],
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.forecast});
  final Forecast forecast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final localNext = forecast.nextAt.toLocal();
    final countdown = _humanCountdown(localNext.difference(now));
    final urgent = localNext.difference(now).inHours <= 24;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${forecast.what}"',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                forecast.basisLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: urgent
                ? scheme.error.withValues(alpha: 0.12)
                : scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'in $countdown',
            style: TextStyle(
              color: urgent ? scheme.error : scheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  static String _humanCountdown(Duration d) {
    if (d.isNegative) return 'soon';
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 14) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}w';
  }
}

// ---- Heatmap ----------------------------------------------------------------

class _Heatmap extends ConsumerWidget {
  const _Heatmap();

  // 8 rows × 3-hour buckets starting at midnight local time.
  static const _hourLabels = ['12a', '3a', '6a', '9a', '12p', '3p', '6p', '9p'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesStreamProvider);
    return entriesAsync.maybeWhen(
      data: (entries) {
        if (entries.length < 5) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _HeatmapCard(entries: entries),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.entries});
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 60));
    final counts = List.generate(8, (_) => List<int>.filled(7, 0));
    var max = 0;
    for (final e in entries) {
      if (e.occurredAt.isBefore(since)) continue;
      final l = e.occurredAt.toLocal();
      final row = (l.hour ~/ 3).clamp(0, 7);
      final col = (l.weekday - 1).clamp(0, 6);
      counts[row][col]++;
      if (counts[row][col] > max) max = counts[row][col];
    }
    if (max == 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'WHEN YOUR FAILURES CLUSTER',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last 60 days, local time',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          _HeatmapGrid(counts: counts, maxCount: max),
          const SizedBox(height: 10),
          _HeatmapLegend(maxCount: max),
        ],
      ),
    );
  }
}

class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.counts, required this.maxCount});
  final List<List<int>> counts;
  final int maxCount;

  static const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 28.0;
        const gap = 4.0;
        final cellW = ((constraints.maxWidth - labelW) / 7) - gap;
        final cellH = math.min(cellW, 24.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: labelW),
                for (var c = 0; c < 7; c++)
                  Padding(
                    padding: EdgeInsets.only(right: c < 6 ? gap : 0),
                    child: SizedBox(
                      width: cellW,
                      child: Text(
                        _weekdayLabels[c],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var r = 0; r < 8; r++)
              Padding(
                padding: EdgeInsets.only(bottom: r < 7 ? gap : 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Text(
                        _Heatmap._hourLabels[r],
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    for (var c = 0; c < 7; c++)
                      Padding(
                        padding: EdgeInsets.only(right: c < 6 ? gap : 0),
                        child: _HeatmapCell(
                          count: counts[r][c],
                          maxCount: maxCount,
                          baseColor: base,
                          width: cellW,
                          height: cellH,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.count,
    required this.maxCount,
    required this.baseColor,
    required this.width,
    required this.height,
  });
  final int count;
  final int maxCount;
  final Color baseColor;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = maxCount == 0 ? 0.0 : (count / maxCount);
    final alpha = count == 0 ? 0.05 : (0.18 + t * 0.72);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend({required this.maxCount});
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('fewer',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                )),
        const SizedBox(width: 6),
        for (final a in [0.18, 0.4, 0.6, 0.85])
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: a),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 6),
        Text('more ($maxCount)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                )),
      ],
    );
  }
}

// ---- Card -------------------------------------------------------------------

class _InsightCard extends ConsumerWidget {
  const _InsightCard({required this.insight, this.isTopPriority = false});
  final Insight insight;
  final bool isTopPriority;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = _paletteFor(insight.kind, Theme.of(context).brightness);
    final scheme = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(entriesStreamProvider);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showEvidenceSheet(context, insight),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.tint,
                palette.tint.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.18),
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconBadge(palette: palette),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _labelFor(insight.kind),
                              style: TextStyle(
                                color: palette.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (isTopPriority) ...[
                              const SizedBox(width: 8),
                              const _TopPriorityPill(),
                            ],
                            const Spacer(),
                            if (insight.evidenceIds.isNotEmpty)
                              _CountPill(
                                count: insight.evidenceIds.length,
                                palette: palette,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          insight.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                    color: scheme.onSurface,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          insight.body,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              entriesAsync.maybeWhen(
                data: (entries) {
                  if (insight.kind == InsightKind.cost ||
                      insight.kind == InsightKind.improvement ||
                      insight.evidenceIds.length < 2) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _SparklineStrip(
                      insight: insight,
                      entries: entries,
                      palette: palette,
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              if (insight.suggestion != null) ...[
                const SizedBox(height: 14),
                _SuggestionBlock(
                  suggestion: insight.suggestion!,
                  palette: palette,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopPriorityPill extends StatelessWidget {
  const _TopPriorityPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.onSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'TOP',
        style: TextStyle(
          color: scheme.surface,
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.palette});
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(palette.icon, color: Colors.white, size: 22),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.palette});
  final int count;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count ${count == 1 ? 'entry' : 'entries'}',
        style: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _SparklineStrip extends StatelessWidget {
  const _SparklineStrip({
    required this.insight,
    required this.entries,
    required this.palette,
  });
  final Insight insight;
  final List<Entry> entries;
  final _Palette palette;

  static const _days = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idSet = insight.evidenceIds.toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final hits = List<bool>.filled(_days, false);
    for (final e in entries) {
      if (e.id == null || !idSet.contains(e.id)) continue;
      final l = e.occurredAt.toLocal();
      final eDay = DateTime(l.year, l.month, l.day);
      final delta = today.difference(eDay).inDays;
      if (delta >= 0 && delta < _days) {
        hits[_days - 1 - delta] = true;
      }
    }
    if (!hits.contains(true)) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '30d',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 1.5;
              final cellW = (c.maxWidth - gap * (_days - 1)) / _days;
              return Row(
                children: [
                  for (var i = 0; i < _days; i++) ...[
                    Container(
                      width: cellW,
                      height: 14,
                      decoration: BoxDecoration(
                        color: hits[i]
                            ? palette.accent
                            : palette.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (i < _days - 1) const SizedBox(width: gap),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'today',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _SuggestionBlock extends StatelessWidget {
  const _SuggestionBlock({required this.suggestion, required this.palette});
  final String suggestion;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    // RAG-borrowed suggestions arrive from the engine prefixed with
    // `From "<what>": <solution>` — strip the prefix and tag the block
    // differently so the user can tell when it's a borrow.
    final isBorrowed = suggestion.startsWith('From "');
    final body = isBorrowed
        ? suggestion.replaceFirst(RegExp(r'^From "[^"]*":\s*'), '')
        : suggestion;
    final borrowedFrom = isBorrowed
        ? RegExp(r'^From "([^"]*)":').firstMatch(suggestion)?.group(1)
        : null;
    final label = isBorrowed ? 'FROM A SIMILAR ENTRY' : 'TRY';
    final icon = isBorrowed
        ? Icons.auto_awesome_rounded
        : Icons.tips_and_updates_outlined;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                if (borrowedFrom != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'matched against "$borrowedFrom"',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Animation --------------------------------------------------------------

class _AnimatedReveal extends StatefulWidget {
  const _AnimatedReveal({required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  State<_AnimatedReveal> createState() => _AnimatedRevealState();
}

class _AnimatedRevealState extends State<_AnimatedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ---- Evidence sheet ---------------------------------------------------------

void _showEvidenceSheet(BuildContext context, Insight insight) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _EvidenceSheet(insight: insight),
  );
}

class _EvidenceSheet extends ConsumerWidget {
  const _EvidenceSheet({required this.insight});
  final Insight insight;

  static const _maxRows = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesStreamProvider);
    final palette = _paletteFor(insight.kind, Theme.of(context).brightness);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _IconBadge(palette: palette),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      insight.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(
                    "Couldn't load entries: $e",
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  data: (entries) =>
                      _evidenceList(context, entries, scrollController),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _evidenceList(
    BuildContext context,
    List<Entry> entries,
    ScrollController scrollController,
  ) {
    if (insight.evidenceIds.isEmpty) {
      return Text(
        'No linked entries yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final byId = {for (final e in entries) if (e.id != null) e.id!: e};
    final found = [
      for (final id in insight.evidenceIds)
        if (byId.containsKey(id)) byId[id]!
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    if (found.isEmpty) {
      return Text(
        'Linked entries are no longer available.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final shown = found.take(_maxRows).toList();
    final remaining = found.length - shown.length;

    return ListView.separated(
      controller: scrollController,
      itemCount: shown.length + (remaining > 0 ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == shown.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '+ $remaining more',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return _EvidenceTile(entry: shown[i]);
      },
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[_formatWhen(entry.occurredAt)];
    if ((entry.cause ?? '').trim().isNotEmpty) {
      subtitleParts.add('cause: ${entry.cause!.trim()}');
    }
    final money = entry.costMoney ?? 0;
    final minutes = entry.costMinutes ?? 0;
    if (money > 0) subtitleParts.add('\$$money');
    if (minutes > 0) subtitleParts.add('$minutes min');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(entry.what),
      subtitle: Text(subtitleParts.join(' · ')),
    );
  }

  String _formatWhen(DateTime utc) {
    final local = utc.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

// ---- States -----------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer.withValues(alpha: 0.5),
              ),
              child: Icon(
                Icons.insights_rounded,
                size: 48,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No patterns yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log a few failures and the engine will start surfacing patterns, '
              'chains, and what they cost you.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Couldn't load insights:\n$message",
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

// ---- Palette ----------------------------------------------------------------

class _Palette {
  const _Palette({
    required this.accent,
    required this.tint,
    required this.icon,
  });
  final Color accent;
  final Color tint;
  final IconData icon;
}

_Palette _paletteFor(InsightKind kind, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  switch (kind) {
    case InsightKind.pattern:
      return _Palette(
        accent: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
        tint: isDark
            ? Colors.blue.shade900.withValues(alpha: 0.25)
            : Colors.blue.shade50,
        icon: Icons.timeline_rounded,
      );
    case InsightKind.chain:
      return _Palette(
        accent: isDark ? Colors.orange.shade300 : Colors.deepOrange.shade600,
        tint: isDark
            ? Colors.deepOrange.shade900.withValues(alpha: 0.25)
            : Colors.deepOrange.shade50,
        icon: Icons.link_rounded,
      );
    case InsightKind.cost:
      return _Palette(
        accent: isDark ? Colors.red.shade300 : Colors.red.shade600,
        tint: isDark
            ? Colors.red.shade900.withValues(alpha: 0.25)
            : Colors.red.shade50,
        icon: Icons.payments_rounded,
      );
    case InsightKind.improvement:
      return _Palette(
        accent: isDark ? Colors.green.shade300 : Colors.green.shade600,
        tint: isDark
            ? Colors.green.shade900.withValues(alpha: 0.25)
            : Colors.green.shade50,
        icon: Icons.trending_up_rounded,
      );
  }
}

String _labelFor(InsightKind kind) {
  switch (kind) {
    case InsightKind.pattern:
      return 'PATTERN';
    case InsightKind.chain:
      return 'CHAIN';
    case InsightKind.cost:
      return 'COST';
    case InsightKind.improvement:
      return 'IMPROVEMENT';
  }
}
