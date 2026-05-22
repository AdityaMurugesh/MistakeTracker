// Owner: Insights
// Renders the output of SuggestionEngine.analyze() as cards.
//
// TODO:
//   - Pull entries via provider, pass to SuggestionEngine.analyze()
//   - Render each Insight as a card, colored by InsightKind:
//       pattern     -> blue
//       chain       -> orange
//       cost        -> red
//       improvement -> green
//   - Tapping a card shows the evidence entries
//   - Empty state: "Log a few failures and patterns will appear here."

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: const Center(child: Text('TODO: insight cards')),
    );
  }
}
