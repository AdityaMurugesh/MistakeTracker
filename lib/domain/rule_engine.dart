// Owner: Insights
// v1 implementation of SuggestionEngine. Pure Dart, no DB access.
//
// Three rule families to implement:
//   1. Recurring cause   — group by `cause`, surface causes appearing in >=3 entries
//   2. Time-of-day pattern — group by (what, day_of_week) or (what, hour); flag >=3 in 30d
//   3. Chain detection   — for each entry, look at next entry within N hours;
//                          surface (A -> B) pairs that appear >=3 times
//
// Plus: suggestion text = user's own past `solution` for the same `what`, if any.
//
// All thresholds are constants below — tweak in one place.

import 'suggestion_engine.dart';
import 'models/entry.dart';
import 'models/insight.dart';

class RuleEngine implements SuggestionEngine {
  // Tweakable thresholds
  static const int minOccurrencesForPattern = 3;
  static const int lookbackDays = 30;
  static const int chainWindowHours = 6;

  @override
  Future<List<Insight>> analyze(List<Entry> entries) async {
    final insights = <Insight>[];

    // TODO: rule 1 — recurring cause
    // TODO: rule 2 — time-of-day pattern
    // TODO: rule 3 — chain detection
    // TODO: build "total cost" insight (sum of costMinutes / costMoney)
    // TODO: build "improvement" insight if a `what` is trending down

    return insights;
  }
}
