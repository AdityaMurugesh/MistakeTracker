// SHARED CONTRACT — changes need 3-person sign-off.
// v1: RuleEngine implements this. v2: LLMEngine can drop in without touching UI.

import 'models/entry.dart';
import 'models/insight.dart';

abstract class SuggestionEngine {
  /// Analyse the given entries and return a list of insights.
  /// Implementations must be pure (no DB access) — caller supplies the data.
  Future<List<Insight>> analyze(List<Entry> entries);
}
