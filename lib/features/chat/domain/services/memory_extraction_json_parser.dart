import 'dart:convert';

class MemoryExtractionJsonParseResult {
  const MemoryExtractionJsonParseResult({
    required this.decoded,
    required this.wasRepaired,
  });

  final Map<String, dynamic> decoded;
  final bool wasRepaired;
}

class MemoryExtractionJsonParser {
  static final RegExp _fencedJsonPattern = RegExp(
    r'^```[a-zA-Z]*\s*|\s*```$',
    multiLine: true,
  );
  static final RegExp _missingClosingQuoteOnKeyPattern = RegExp(
    r'"([A-Za-z_][A-Za-z0-9_]*)\s*:',
  );
  static final RegExp _unquotedKeyPattern = RegExp(
    r'([,{]\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*:)',
  );
  static final RegExp _trailingCommaPattern = RegExp(r',(\s*[}\]])');

  static MemoryExtractionJsonParseResult? parse(String rawContent) {
    final jsonText = extractJsonObject(rawContent);
    if (jsonText == null) {
      return null;
    }

    for (final candidate in _candidateDocuments(jsonText)) {
      try {
        final decoded = jsonDecode(candidate.text);
        if (decoded is! Map) {
          continue;
        }
        return MemoryExtractionJsonParseResult(
          decoded: Map<String, dynamic>.from(decoded),
          wasRepaired: candidate.wasRepaired,
        );
      } catch (_) {
        // Keep trying repaired candidates.
      }
    }

    return null;
  }

  static String? extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll(_fencedJsonPattern, '').trim();
    }

    final first = text.indexOf('{');
    final last = text.lastIndexOf('}');
    if (first < 0 || last <= first) {
      return null;
    }
    return text.substring(first, last + 1);
  }

  static List<_JsonCandidate> _candidateDocuments(String jsonText) {
    final seen = <String>{};
    final candidates = <_JsonCandidate>[];

    void add(String text, {required bool repaired}) {
      if (seen.add(text)) {
        candidates.add(_JsonCandidate(text: text, wasRepaired: repaired));
      }
    }

    add(jsonText, repaired: false);

    final normalizedQuotes = _normalizeQuotes(jsonText);
    add(normalizedQuotes, repaired: normalizedQuotes != jsonText);

    final repaired = _repairCommonIssues(normalizedQuotes);
    add(repaired, repaired: repaired != jsonText);

    return candidates;
  }

  static String _normalizeQuotes(String text) {
    return text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('„', '"')
        .replaceAll('‟', '"')
        .replaceAll('’', "'")
        .replaceAll('‘', "'");
  }

  static String _repairCommonIssues(String text) {
    var repaired = text;

    repaired = repaired.replaceAllMapped(
      _missingClosingQuoteOnKeyPattern,
      (match) => '"${match.group(1)}":',
    );

    repaired = repaired.replaceAllMapped(
      _unquotedKeyPattern,
      (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
    );

    repaired = repaired.replaceAllMapped(
      _trailingCommaPattern,
      (match) => match.group(1) ?? '',
    );
    return repaired;
  }
}

class _JsonCandidate {
  const _JsonCandidate({
    required this.text,
    required this.wasRepaired,
  });

  final String text;
  final bool wasRepaired;
}
