// Owner: Insights (v2)
// Third seam alongside SuggestionEngine and NarrativeEngine: takes the
// user's recent entries AND the rule engine's forward-looking forecasts and
// produces a short prose "looking ahead" paragraph that reasons about
// upcoming risk windows and suggests one preemptive action.
//
// Kept as its own interface because the input shape is different
// (entries + forecasts vs entries alone) and the output is forward-looking
// rather than retrospective. Null means "nothing worth surfacing" or
// "AI disabled" — the card is hidden in either case.

import 'models/entry.dart';
import 'models/forecast.dart';

abstract class OutlookEngine {
  Future<String?> outlook(List<Entry> entries, List<Forecast> forecasts);
}
