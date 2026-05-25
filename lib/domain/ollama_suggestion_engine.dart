// Owner: Insights (v2)
// LLM-backed SuggestionEngine. Talks to a local Ollama server over HTTP.
//
// Demonstrates the SuggestionEngine seam: same interface as RuleEngine,
// swapped in via providers.dart when the user enables AI insights.
//
// RAG (lightweight): we don't send the entire entry log. We rank entries by
// recency-weighted severity, take the top N, and stringify them compactly.
// This keeps the prompt small (~1-2k tokens) so generation finishes in
// seconds even on a 3B model like llama3.2.
//
// Output is constrained to JSON via Ollama's `format: 'json'` parameter and
// parsed into List<Insight>. Any failure (network, timeout, bad JSON) throws
// so the FallbackSuggestionEngine wrapper can drop back to RuleEngine.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/entry.dart';
import 'models/forecast.dart';
import 'models/insight.dart';
import 'narrative_engine.dart';
import 'outlook_engine.dart';
import 'suggestion_engine.dart';

class OllamaSuggestionEngine
    implements SuggestionEngine, NarrativeEngine, OutlookEngine {
  final String host;
  final String model;
  final Duration timeout;
  final int maxEntriesInPrompt;
  final http.Client _client;

  OllamaSuggestionEngine({
    this.host = 'http://10.0.2.2:11434',
    this.model = 'llama3.2',
    this.timeout = const Duration(seconds: 45),
    this.maxEntriesInPrompt = 40,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<List<Insight>> analyze(List<Entry> entries) async {
    if (entries.isEmpty) return const [];

    final ranked = _rankForPrompt(entries);
    final prompt = _buildPrompt(ranked);

    final uri = Uri.parse('$host/api/generate');
    final res = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'stream': false,
            'format': 'json',
            'options': {
              'temperature': 0.4,
              'num_predict': 1024,
            },
          }),
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw OllamaEngineException(
        'Ollama returned HTTP ${res.statusCode}: ${res.body}',
      );
    }

    final envelope = jsonDecode(res.body) as Map<String, Object?>;
    final responseText = envelope['response'] as String?;
    if (responseText == null || responseText.isEmpty) {
      throw const OllamaEngineException('Ollama response had empty body');
    }

    return _parseInsights(responseText, ranked);
  }

  /// 1-2 sentence personalised summary of the last 7 days, for the hero
  /// card. Returns null when there's nothing recent worth surfacing.
  @override
  Future<String?> narrative(List<Entry> entries) async {
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));
    final recent = entries
        .where((e) => !e.occurredAt.isBefore(weekStart))
        .toList(growable: false);
    if (recent.isEmpty) return null;

    final buf = StringBuffer();
    buf.writeln(
      "You are summarising one week of a user's failure log for a hero card. Write 1-2 short sentences in second person, addressing the user. Be specific (mention what happened most, costs, or a notable cause) but warm — coach, not judge. No emoji, no headers, no markdown.",
    );
    buf.writeln();
    buf.writeln("Last 7 days:");
    for (final e in recent) {
      buf.write('- "${e.what}" on ${_fmtDate(e.occurredAt)}');
      buf.write(' (sev ${e.severity}');
      if (e.costMinutes != null) buf.write(', ${e.costMinutes}min');
      if (e.costMoney != null) buf.write(', \$${e.costMoney}');
      buf.write(')');
      if (e.cause != null && e.cause!.isNotEmpty) buf.write(' cause: ${e.cause}');
      buf.writeln();
    }
    buf.writeln();
    buf.writeln('Write the summary now. Plain text only.');

    final uri = Uri.parse('$host/api/generate');
    final res = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'prompt': buf.toString(),
            'stream': false,
            'options': {
              'temperature': 0.6,
              'num_predict': 160,
            },
          }),
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw OllamaEngineException(
        'Ollama narrative returned HTTP ${res.statusCode}: ${res.body}',
      );
    }

    final envelope = jsonDecode(res.body) as Map<String, Object?>;
    final text = (envelope['response'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw const OllamaEngineException('Ollama narrative response was empty');
    }
    return text;
  }

  /// Forward-looking: takes the rule engine's structured forecasts plus a
  /// small RAG'd entry sample and writes a 2-3 sentence "looking ahead"
  /// paragraph naming a specific upcoming risk window and one preemptive
  /// action. Returns null when there's nothing actionable to say.
  @override
  Future<String?> outlook(
    List<Entry> entries,
    List<Forecast> forecasts,
  ) async {
    if (forecasts.isEmpty) return null;
    final topForecasts = forecasts.take(3).toList();
    final ranked = _rankForPrompt(entries).take(20).toList();

    final buf = StringBuffer();
    buf.writeln(
      "You are writing a forward-looking 'heads up' paragraph for a user's failure tracker. The user logs everyday failures; the rule engine has projected the next likely risk windows below. Use the past entries as context to explain WHY each window is risky and suggest ONE specific preemptive action drawn from the user's own past_solution fields when possible. Write 2-3 short sentences, second person, warm coach tone. No emoji, no headers, no markdown. Do not invent forecasts that are not listed.",
    );
    buf.writeln();
    buf.writeln('Upcoming risk windows (soonest first):');
    for (final f in topForecasts) {
      buf.write('- "${f.what}" projected for ${_fmtDate(f.nextAt)}');
      buf.write(' — basis: ${f.basisLabel} (${f.basis} prior occurrences)');
      buf.writeln();
    }
    buf.writeln();
    buf.writeln('Recent context (most relevant first):');
    for (final e in ranked) {
      buf.write('- "${e.what}" on ${_fmtDate(e.occurredAt)}');
      buf.write(' (sev ${e.severity})');
      if (e.cause != null && e.cause!.isNotEmpty) buf.write(' cause: ${e.cause}');
      if (e.solution != null && e.solution!.isNotEmpty) {
        buf.write(' past_solution: ${e.solution}');
      }
      buf.writeln();
    }
    buf.writeln();
    buf.writeln(
      'Write the looking-ahead paragraph now. Plain text only. Be specific (name the day, the activity, the preemptive action).',
    );

    final uri = Uri.parse('$host/api/generate');
    final res = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'prompt': buf.toString(),
            'stream': false,
            'options': {
              'temperature': 0.5,
              'num_predict': 220,
            },
          }),
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw OllamaEngineException(
        'Ollama outlook returned HTTP ${res.statusCode}: ${res.body}',
      );
    }

    final envelope = jsonDecode(res.body) as Map<String, Object?>;
    final text = (envelope['response'] as String?)?.trim();
    if (text == null || text.isEmpty) {
      throw const OllamaEngineException('Ollama outlook response was empty');
    }
    return text;
  }

  /// Score = severity * recency_decay. Sorted high-to-low, capped at
  /// [maxEntriesInPrompt]. This is the RAG step — we send the LLM only the
  /// entries most likely to be informative.
  List<Entry> _rankForPrompt(List<Entry> entries) {
    final now = DateTime.now();
    final scored = entries.map((e) {
      final ageDays = now.difference(e.occurredAt).inDays.clamp(0, 365);
      final recency = 1.0 / (1.0 + ageDays / 14.0); // half-life ~14 days
      final score = e.severity * recency;
      return (entry: e, score: score);
    }).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(maxEntriesInPrompt).map((s) => s.entry).toList();
  }

  String _buildPrompt(List<Entry> ranked) {
    final buf = StringBuffer();
    buf.writeln(
      'You are an analyst reviewing a personal failure log. Each entry is something the user did or experienced that they wanted to avoid. Find concrete, useful patterns and suggest what they could do differently.',
    );
    buf.writeln();
    buf.writeln('Entries (most relevant first):');
    for (final e in ranked) {
      buf.write('- id=${e.id ?? "?"} ');
      buf.write('"${e.what}" ');
      buf.write('on ${_fmtDate(e.occurredAt)} ');
      buf.write('(severity ${e.severity}');
      if (e.costMinutes != null) buf.write(', ${e.costMinutes}min');
      if (e.costMoney != null) buf.write(', \$${e.costMoney}');
      buf.write(')');
      if (e.cause != null && e.cause!.isNotEmpty) buf.write(' cause: ${e.cause}');
      if (e.context != null && e.context!.isNotEmpty) {
        buf.write(' context: ${e.context}');
      }
      if (e.solution != null && e.solution!.isNotEmpty) {
        buf.write(' past_solution: ${e.solution}');
      }
      buf.writeln();
    }
    buf.writeln();
    buf.writeln(
      'Respond with a JSON object: {"insights": [ ... ]}. Each insight object must have:',
    );
    buf.writeln('  "kind": one of "pattern", "chain", "cost", "improvement"');
    buf.writeln('  "title": a short headline (max 8 words)');
    buf.writeln(
      '  "body": one or two sentences describing the pattern and why it matters',
    );
    buf.writeln(
      '  "evidence_ids": array of entry ids (integers, from the list above) that support this insight',
    );
    buf.writeln(
      '  "suggestion": (optional) a concrete next step the user could try, drawn from their own past_solution fields when relevant',
    );
    buf.writeln();
    buf.writeln(
      'Return 3-6 insights. Prefer specific observations over generic advice. Do not invent entries that are not listed above.',
    );
    return buf.toString();
  }

  List<Insight> _parseInsights(String body, List<Entry> ranked) {
    final Map<String, Object?> root;
    try {
      root = jsonDecode(body) as Map<String, Object?>;
    } catch (e) {
      throw OllamaEngineException('Ollama response was not valid JSON: $e');
    }

    final raw = root['insights'];
    if (raw is! List) {
      throw const OllamaEngineException(
        'Ollama response missing "insights" array',
      );
    }

    final validIds = ranked.map((e) => e.id).whereType<int>().toSet();

    final out = <Insight>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final kindStr = (item['kind'] as String?)?.toLowerCase() ?? 'pattern';
      final title = (item['title'] as String?)?.trim();
      final bodyText = (item['body'] as String?)?.trim();
      if (title == null || title.isEmpty || bodyText == null || bodyText.isEmpty) {
        continue;
      }
      final evidenceRaw = item['evidence_ids'];
      final evidence = <int>[];
      if (evidenceRaw is List) {
        for (final v in evidenceRaw) {
          final asInt = v is int ? v : int.tryParse(v.toString());
          if (asInt != null && validIds.contains(asInt)) evidence.add(asInt);
        }
      }
      final suggestion = (item['suggestion'] as String?)?.trim();
      out.add(Insight(
        kind: _kindFromString(kindStr),
        title: title,
        body: bodyText,
        evidenceIds: evidence,
        suggestion: (suggestion != null && suggestion.isNotEmpty) ? suggestion : null,
      ));
    }

    if (out.isEmpty) {
      throw const OllamaEngineException(
        'Ollama returned no usable insights',
      );
    }
    return out;
  }

  InsightKind _kindFromString(String s) {
    switch (s) {
      case 'chain':
        return InsightKind.chain;
      case 'cost':
        return InsightKind.cost;
      case 'improvement':
        return InsightKind.improvement;
      case 'pattern':
      default:
        return InsightKind.pattern;
    }
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  void dispose() => _client.close();
}

class OllamaEngineException implements Exception {
  final String message;
  const OllamaEngineException(this.message);
  @override
  String toString() => 'OllamaEngineException: $message';
}
