// Owner: Insights
// Lightweight on-device semantic similarity for short user-typed strings.
//
// v1 approach (pure Dart, no model files, runs on web):
//   1. Tokenize + stem (strip ing/ed/es/s, simple double-letter trim)
//   2. Resolve each stem against a curated synonym table to a canonical root
//   3. Drop stopwords; sort and join → conceptKey
//   4. similarity() also exposes a character-bigram/trigram cosine for the
//      RAG-style retrieval path where exact key match is too strict.
//
// v2 extension point: swap this class for an EmbeddingSemantic that loads a
// TFLite sentence-transformer model. The public API (conceptKey, similarity)
// is intentionally small so the rule engine doesn't change. See DESIGN.md
// "What's deliberately out of v1" — same hook as SuggestionEngine.

import 'dart:math' as math;

class Semantic {
  const Semantic();

  /// Canonical "concept key" for a user-typed string. Returns the same key
  /// for spelling variants, plural/singular, common synonyms, and reorderings
  /// ("missed gym" and "skipped workout" both → "skip workout").
  ///
  /// Used by the rule engine to group entries by meaning, not by spelling.
  String? conceptKey(String? s) {
    if (s == null) return null;
    final tokens = _tokenize(s);
    if (tokens.isEmpty) return null;
    final stems = tokens.map(_stem);
    // Dedupe so "scrolled phone" and "scrolling" both collapse to one
    // canonical "phone" token instead of "phone phone" vs "phone".
    final resolved = {for (final t in stems) _synonyms[t] ?? t};
    final filtered = resolved.where((t) => !_stopwords.contains(t)).toList();
    if (filtered.isEmpty) return null;
    filtered.sort();
    return filtered.join(' ');
  }

  /// Cosine similarity in [0.0, 1.0] over character bigrams + trigrams,
  /// boosted to 1.0 when the two strings share a concept key. Used by the
  /// RAG suggestion path to find the user's semantically closest past
  /// entries even when concept-key grouping would have missed them.
  double similarity(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0.0;
    if (na == nb) return 1.0;
    final ka = conceptKey(a);
    final kb = conceptKey(b);
    if (ka != null && kb != null && ka == kb) return 1.0;
    return _charNgramCosine(na, nb);
  }

  String _normalize(String s) => s.trim().toLowerCase();

  List<String> _tokenize(String s) {
    final n = _normalize(s);
    return n
        .split(RegExp(r'[\s\-_/,.]+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  // Crude English stemmer — adequate for short user-typed phrases.
  //
  // Thresholds are conservative: -ing/-ed/-es strip only when the input is
  // at least 6 chars, -s when at least 5, so short words like "tired" and
  // "bored" pass through unchanged. The doubling-trim that turns "skipp" →
  // "skip" stays gated on -ss / -ll / -ff which are usually root spellings
  // (miss, fall, off), not doubling artifacts.
  String _stem(String t) {
    var s = t;
    var stripped = false;
    if (s.length > 5 && s.endsWith('ing')) {
      s = s.substring(0, s.length - 3);
      stripped = true;
    } else if (s.length > 5 && s.endsWith('ed')) {
      s = s.substring(0, s.length - 2);
      stripped = true;
    } else if (s.length > 5 && s.endsWith('es')) {
      s = s.substring(0, s.length - 2);
      stripped = true;
    } else if (s.length > 4 && s.endsWith('s')) {
      s = s.substring(0, s.length - 1);
      stripped = true;
    }
    if (stripped &&
        s.length > 3 &&
        s[s.length - 1] == s[s.length - 2] &&
        !'aeiou'.contains(s[s.length - 1]) &&
        !s.endsWith('ss') &&
        !s.endsWith('ll') &&
        !s.endsWith('ff')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // Stems that contribute little semantic signal and would otherwise split
  // groups that ought to merge. "didnt work out today" should not depend
  // on the word "today" matching.
  static const _stopwords = <String>{
    'a', 'an', 'the',
    'today', 'tonight', 'tomorrow', 'yesterday',
    'morning', 'evening', 'afternoon', 'night',
    'no', 'not', 'didnt', 'didn', 'dont', 'don',
    'my', 'me', 'i', 'in', 'on', 'at', 'with', 'to', 'for', 'of', 'and',
    'about', 'because', 'really', 'very', 'too', 'so',
  };

  // Variant stem → canonical root. Curated for the v1 demo around the
  // categories the seed data uses; expand as the user logs new vocab.
  static const Map<String, String> _synonyms = {
    // Workout cluster
    'gym': 'workout',
    'exercise': 'workout',
    'workout': 'workout',
    'training': 'workout',
    'train': 'workout',
    'lift': 'workout',
    'run': 'workout',
    'cardio': 'workout',
    'jog': 'workout',
    'yoga': 'workout',

    // Skip/miss cluster (the "negative action")
    'miss': 'skip',
    'skip': 'skip',
    'forget': 'skip',
    'forgot': 'skip',
    'avoid': 'skip',
    'flake': 'skip',

    // Sleep cluster
    'sleep': 'sleep',
    'nap': 'sleep',
    'rest': 'sleep',
    'bedtime': 'sleep',
    'bed': 'sleep',

    // Tired cluster
    'tire': 'tired',
    'tired': 'tired',
    'exhaust': 'tired',
    'sleepy': 'tired',
    'drain': 'tired',
    'fatigu': 'tired',
    'burnt': 'tired',
    'burnout': 'tired',

    // Stressed cluster
    'stress': 'stressed',
    'stressed': 'stressed',
    'anxiou': 'stressed',
    'anxious': 'stressed',
    'overwhelm': 'stressed',
    'panic': 'stressed',
    'worri': 'stressed',
    'nerv': 'stressed',

    // Bored cluster
    'bore': 'bored',
    'bored': 'bored',
    'restles': 'bored',
    'antsi': 'bored',

    // Spend / purchase cluster
    'spend': 'spend',
    'spent': 'spend',
    'purchase': 'spend',
    'buy': 'spend',
    'bought': 'spend',
    'shop': 'spend',
    'order': 'spend',
    'amazon': 'spend',

    // Impulse marker (often paired with spend)
    'impuls': 'impulse',
    'impulsiv': 'impulse',

    // Eat / snack cluster
    'snack': 'eat',
    'binge': 'eat',
    'eat': 'eat',
    'ate': 'eat',
    'overeat': 'eat',
    'overat': 'eat',
    'junk': 'eat',
    'sweet': 'eat',
    'dessert': 'eat',
    'sugar': 'eat',

    // Phone / scrolling cluster
    'phone': 'phone',
    'scroll': 'phone',
    'instagram': 'phone',
    'tiktok': 'phone',
    'twitter': 'phone',
    'reddit': 'phone',
    'youtub': 'phone',
    'youtube': 'phone',
    'doomscroll': 'phone',
    'social': 'phone',
    'media': 'phone',

    // Conflict cluster
    'argu': 'conflict',
    'argum': 'conflict',
    'argument': 'conflict',
    'fight': 'conflict',
    'fought': 'conflict',
    'conflict': 'conflict',
    'yell': 'conflict',
    'shout': 'conflict',
    'roommat': 'roommate',

    // Procrastinate cluster
    'procrastinat': 'procrastinate',
    'delay': 'procrastinate',
    'postpon': 'procrastinate',
    'put': 'procrastinate', // common in "put off"
    'off': 'procrastinate',

    // Breakfast / meal markers
    'breakfast': 'breakfast',
    'lunch': 'lunch',
    'dinner': 'dinner',
    'meal': 'meal',

    // Couldn't sleep / insomnia cluster
    'insomnia': 'insomnia',
    'awak': 'insomnia',
    'awake': 'insomnia',
    'restless': 'insomnia',

    // Couldn cluster (couldn't = couldn) — couldn't sleep → "insomnia sleep"
    'couldn': 'cant',
    'cant': 'cant',
    'unabl': 'cant',
  };

  double _charNgramCosine(String a, String b) {
    final va = _ngramCounts(a);
    final vb = _ngramCounts(b);
    if (va.isEmpty || vb.isEmpty) return 0.0;
    var dot = 0;
    for (final entry in va.entries) {
      final ob = vb[entry.key];
      if (ob != null) dot += entry.value * ob;
    }
    var ma = 0;
    for (final v in va.values) {
      ma += v * v;
    }
    var mb = 0;
    for (final v in vb.values) {
      mb += v * v;
    }
    return dot / (math.sqrt(ma) * math.sqrt(mb));
  }

  Map<String, int> _ngramCounts(String s) {
    final padded = ' $s ';
    final m = <String, int>{};
    for (final n in const [2, 3]) {
      for (var i = 0; i + n <= padded.length; i++) {
        final g = padded.substring(i, i + n);
        m[g] = (m[g] ?? 0) + 1;
      }
    }
    return m;
  }
}
