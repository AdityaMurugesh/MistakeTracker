// Owner: Insights
// Renders the output of SuggestionEngine.analyze() as cards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/entry.dart';
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
                    color: palette.accent.withValues(alpha: 0.08),
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
    isScrollControlled: true,
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(insight.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: entriesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text(
                    "Couldn't load entries: $e",
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    if (minutes > 0) subtitleParts.add('${minutes}m');

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
