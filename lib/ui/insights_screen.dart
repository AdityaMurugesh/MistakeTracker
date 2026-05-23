// Owner: Insights
// Renders the output of SuggestionEngine.analyze() as cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/insight.dart';
import '../state/providers.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(message: err.toString()),
        data: (insights) {
          if (insights.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(insightsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: insights.length,
              itemBuilder: (context, i) => _InsightCard(insight: insights[i]),
            ),
          );
        },
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(insight.kind, Theme.of(context).brightness);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEvidenceSheet(context, insight),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: palette.accent, width: 4)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(palette.icon, color: palette.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _labelFor(insight.kind),
                    style: TextStyle(
                      color: palette.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                insight.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(insight.body, style: Theme.of(context).textTheme.bodyMedium),
              if (insight.suggestion != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: palette.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          insight.suggestion!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _showEvidenceSheet(BuildContext context, Insight insight) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.title, style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            insight.evidenceIds.isEmpty
                ? 'No linked entries yet.'
                : 'Based on ${insight.evidenceIds.length} entries.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          // TODO(insights): once entriesStreamProvider exists, look up the
          // Entry rows for evidenceIds and show them here.
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No patterns yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Log a few failures and patterns will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _Palette {
  const _Palette({required this.accent, required this.icon});
  final Color accent;
  final IconData icon;
}

_Palette _paletteFor(InsightKind kind, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  switch (kind) {
    case InsightKind.pattern:
      return _Palette(
        accent: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
        icon: Icons.timeline,
      );
    case InsightKind.chain:
      return _Palette(
        accent: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
        icon: Icons.link,
      );
    case InsightKind.cost:
      return _Palette(
        accent: isDark ? Colors.red.shade300 : Colors.red.shade700,
        icon: Icons.payments_outlined,
      );
    case InsightKind.improvement:
      return _Palette(
        accent: isDark ? Colors.green.shade300 : Colors.green.shade700,
        icon: Icons.trending_up,
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
