// Owner: Insights
// Unit tests for the semantic similarity layer.

import 'package:flutter_test/flutter_test.dart';
import 'package:mistake_tracker/domain/semantic.dart';

void main() {
  const semantic = Semantic();

  group('Semantic.conceptKey', () {
    test('returns null for null / empty / whitespace', () {
      expect(semantic.conceptKey(null), isNull);
      expect(semantic.conceptKey(''), isNull);
      expect(semantic.conceptKey('   '), isNull);
    });

    test('case- and whitespace-insensitive', () {
      expect(semantic.conceptKey('Tired'), equals(semantic.conceptKey('tired')));
      expect(
          semantic.conceptKey('  TIRED '), equals(semantic.conceptKey('tired')));
    });

    test('merges "missed gym" and "skipped workout" into the same key', () {
      expect(semantic.conceptKey('missed gym'),
          equals(semantic.conceptKey('skipped workout')));
    });

    test('merges "exhausted" and "tired" via synonym table', () {
      expect(semantic.conceptKey('exhausted'),
          equals(semantic.conceptKey('tired')));
    });

    test('stems plural / progressive variants', () {
      // "scrolling" → "scroll" → "phone"
      expect(semantic.conceptKey('scrolling'),
          equals(semantic.conceptKey('scrolled phone')));
    });

    test('different concepts produce different keys', () {
      expect(semantic.conceptKey('missed workout'),
          isNot(equals(semantic.conceptKey('impulse purchase'))));
      expect(semantic.conceptKey('tired'),
          isNot(equals(semantic.conceptKey('stressed'))));
    });

    test('drops stopwords from the key', () {
      // "I missed the gym today" should still concept-key to "skip workout".
      expect(semantic.conceptKey('I missed the gym today'),
          equals(semantic.conceptKey('missed gym')));
    });
  });

  group('Semantic.similarity', () {
    test('identical strings → 1.0', () {
      expect(semantic.similarity('missed gym', 'missed gym'), equals(1.0));
    });

    test('shared concept key → 1.0', () {
      expect(
          semantic.similarity('missed gym', 'skipped workout'), equals(1.0));
    });

    test('unrelated short strings → low score', () {
      // "zzz" vs "apple" — basically zero shared bigrams.
      final sim = semantic.similarity('zzz', 'apple');
      expect(sim, lessThan(0.2));
    });

    test('related-but-different strings score in the middle', () {
      // n-gram cosine fallback should put related strings comfortably above
      // unrelated noise, even when the concept keys differ.
      final sim =
          semantic.similarity('late night scrolling', 'scrolled phone in bed');
      expect(sim, greaterThan(0.25));
    });

    test('empty input → 0.0', () {
      expect(semantic.similarity('', 'missed gym'), equals(0.0));
      expect(semantic.similarity('missed gym', ''), equals(0.0));
    });
  });
}
