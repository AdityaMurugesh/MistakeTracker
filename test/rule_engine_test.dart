// Owner: Insights
// Unit tests for the brain of the app. Most important test file.
//
// TODO test cases:
//   - Empty entries -> empty insights
//   - 3+ entries with same cause -> one "recurring cause" insight
//   - Entries with same (what, day_of_week) >=3 times -> one "pattern" insight
//   - A->B sequence appearing 3+ times within window -> one "chain" insight
//   - Improving trend on a `what` -> one "improvement" insight
//   - Cost aggregation across entries -> one "cost" insight

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/domain/rule_engine.dart';

void main() {
  group('RuleEngine', () {
    test('returns no insights for empty input', () async {
      final engine = RuleEngine();
      final insights = await engine.analyze([]);
      expect(insights, isEmpty);
    });

    // TODO: add more tests as the engine is implemented
  });
}
