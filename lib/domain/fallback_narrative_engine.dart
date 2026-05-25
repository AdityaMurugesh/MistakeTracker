// Owner: Insights (v2)
// Same demo-safety pattern as FallbackSuggestionEngine, applied to the
// NarrativeEngine seam: try primary, drop to fallback on any error.

import 'package:flutter/foundation.dart' show debugPrint;

import 'models/entry.dart';
import 'narrative_engine.dart';

class FallbackNarrativeEngine implements NarrativeEngine {
  final NarrativeEngine primary;
  final NarrativeEngine fallback;
  final void Function(Object error, StackTrace stack)? onFallback;

  FallbackNarrativeEngine({
    required this.primary,
    required this.fallback,
    this.onFallback,
  });

  @override
  Future<String?> narrative(List<Entry> entries) async {
    try {
      return await primary.narrative(entries);
    } catch (e, st) {
      onFallback?.call(e, st);
      debugPrint('[AI] primary narrative failed, falling back: $e');
      return fallback.narrative(entries);
    }
  }
}
