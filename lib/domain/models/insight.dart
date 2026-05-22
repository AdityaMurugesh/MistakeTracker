// SHARED CONTRACT — changes need 3-person sign-off.
// What the SuggestionEngine returns. Insights screen renders these as cards.

enum InsightKind { pattern, chain, cost, improvement }

class Insight {
  final InsightKind kind;
  final String title;
  final String body;
  final List<int> evidenceIds; // ids of Entries that support this insight
  final String? suggestion; // optional: derived prevention tip

  const Insight({
    required this.kind,
    required this.title,
    required this.body,
    this.evidenceIds = const [],
    this.suggestion,
  });
}
