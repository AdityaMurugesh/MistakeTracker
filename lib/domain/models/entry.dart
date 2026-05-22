// SHARED CONTRACT — changes need 3-person sign-off.
// The core data class. Every other module reads/writes Entries.

class Entry {
  final int? id;
  final String kind; // 'failure' (v1) | 'win' (v2, deferred)
  final String what; // e.g. "missed workout", "impulse purchase"
  final String? cause; // user's guess at the trigger
  final DateTime occurredAt; // stored UTC, displayed local
  final String? context; // free text: where, with whom
  final int severity; // 1..5
  final int? costMinutes;
  final int? costMoney; // currency-agnostic int
  final String? moodImpact;
  final String? solution; // "my solution" — what the user did to fix it
  final DateTime createdAt;

  const Entry({
    this.id,
    this.kind = 'failure',
    required this.what,
    this.cause,
    required this.occurredAt,
    this.context,
    this.severity = 3,
    this.costMinutes,
    this.costMoney,
    this.moodImpact,
    this.solution,
    required this.createdAt,
  });

  Entry copyWith({
    int? id,
    String? kind,
    String? what,
    String? cause,
    DateTime? occurredAt,
    String? context,
    int? severity,
    int? costMinutes,
    int? costMoney,
    String? moodImpact,
    String? solution,
    DateTime? createdAt,
  }) {
    return Entry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      what: what ?? this.what,
      cause: cause ?? this.cause,
      occurredAt: occurredAt ?? this.occurredAt,
      context: context ?? this.context,
      severity: severity ?? this.severity,
      costMinutes: costMinutes ?? this.costMinutes,
      costMoney: costMoney ?? this.costMoney,
      moodImpact: moodImpact ?? this.moodImpact,
      solution: solution ?? this.solution,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind,
        'what': what,
        'cause': cause,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'context': context,
        'severity': severity,
        'cost_minutes': costMinutes,
        'cost_money': costMoney,
        'mood_impact': moodImpact,
        'solution': solution,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int?,
        kind: m['kind'] as String? ?? 'failure',
        what: m['what'] as String,
        cause: m['cause'] as String?,
        occurredAt: DateTime.parse(m['occurred_at'] as String),
        context: m['context'] as String?,
        severity: (m['severity'] as int?) ?? 3,
        costMinutes: m['cost_minutes'] as int?,
        costMoney: m['cost_money'] as int?,
        moodImpact: m['mood_impact'] as String?,
        solution: m['solution'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
