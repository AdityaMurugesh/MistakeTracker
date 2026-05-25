// Owner: Insights (v2)
// Demo-safety wrapper: try `primary`, fall back to `fallback` on any error.
//
// Why: the LLM path can fail in lots of small ways (Ollama not running,
// model not pulled, network blip, malformed JSON). Catching here keeps the
// Insights screen functional even when the AI path is broken.

import 'package:flutter/foundation.dart' show debugPrint;

import 'models/entry.dart';
import 'models/insight.dart';
import 'suggestion_engine.dart';

class FallbackSuggestionEngine implements SuggestionEngine {
  final SuggestionEngine primary;
  final SuggestionEngine fallback;
  final void Function(Object error, StackTrace stack)? onFallback;

  FallbackSuggestionEngine({
    required this.primary,
    required this.fallback,
    this.onFallback,
  });

  @override
  Future<List<Insight>> analyze(List<Entry> entries) async {
    try {
      return await primary.analyze(entries);
    } catch (e, st) {
      onFallback?.call(e, st);
      debugPrint('[AI] primary engine failed, falling back: $e');
      return fallback.analyze(entries);
    }
  }
}
