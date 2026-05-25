// Owner: Insights (v2)
// Same pattern as the other fallback wrappers: try primary, drop to
// fallback on any error. For outlook, the rule-engine fallback returns
// null, so a failed LLM call simply hides the card instead of breaking
// the screen.

import 'package:flutter/foundation.dart' show debugPrint;

import 'models/entry.dart';
import 'models/forecast.dart';
import 'outlook_engine.dart';

class FallbackOutlookEngine implements OutlookEngine {
  final OutlookEngine primary;
  final OutlookEngine fallback;
  final void Function(Object error, StackTrace stack)? onFallback;

  FallbackOutlookEngine({
    required this.primary,
    required this.fallback,
    this.onFallback,
  });

  @override
  Future<String?> outlook(List<Entry> entries, List<Forecast> forecasts) async {
    try {
      return await primary.outlook(entries, forecasts);
    } catch (e, st) {
      onFallback?.call(e, st);
      debugPrint('[AI] primary outlook failed, falling back: $e');
      return fallback.outlook(entries, forecasts);
    }
  }
}
