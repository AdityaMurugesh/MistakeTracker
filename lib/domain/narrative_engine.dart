// Owner: Insights (v2)
// Separate seam from SuggestionEngine: produces a single short prose summary
// of the user's recent activity, suitable for the Insights hero card.
//
// Kept distinct from SuggestionEngine on purpose — narrative is a different
// shape of output (one string vs a list of structured Insights) and we want
// the SuggestionEngine SHARED CONTRACT to stay unchanged.

import 'models/entry.dart';

abstract class NarrativeEngine {
  /// Returns a 1-2 sentence personalised summary of the user's last 7 days.
  /// Returns null when there's nothing recent worth surfacing.
  Future<String?> narrative(List<Entry> entries);
}
