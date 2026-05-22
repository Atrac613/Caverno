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
    final jsonObjects = extractJsonObjects(rawContent);
    if (jsonObjects.isEmpty) {
      return null;
    }

    MemoryExtractionJsonParseResult? fallback;
    for (final jsonText in jsonObjects) {
      for (final candidate in _candidateDocuments(jsonText)) {
        try {
          final decoded = jsonDecode(candidate.text);
          if (decoded is! Map) {
            continue;
          }
          final result = MemoryExtractionJsonParseResult(
            decoded: Map<String, dynamic>.from(decoded),
            wasRepaired: candidate.wasRepaired,
          );
          if (_looksLikeMemoryExtraction(result.decoded)) {
            return result;
          }
          fallback ??= result;
        } catch (_) {
          // Keep trying repaired candidates.
        }
      }
    }

    return fallback;
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

  static List<String> extractJsonObjects(String raw) {
    final text = _stripOuterFence(raw.trim());
    final candidates = <String>[];
    final seen = <String>{};

    final broadCandidate = extractJsonObject(text);
    if (broadCandidate != null && seen.add(broadCandidate)) {
      candidates.add(broadCandidate);
    }

    for (final candidate in _balancedJsonObjects(text)) {
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
    }

    return candidates;
  }

  static String _stripOuterFence(String text) {
    if (!text.startsWith('```')) {
      return text;
    }
    return text.replaceAll(_fencedJsonPattern, '').trim();
  }

  static Iterable<String> _balancedJsonObjects(String text) sync* {
    for (var start = 0; start < text.length; start += 1) {
      if (text.codeUnitAt(start) != 0x7b) {
        continue;
      }
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = start; index < text.length; index += 1) {
        final codeUnit = text.codeUnitAt(index);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (codeUnit == 0x5c) {
            escaped = true;
          } else if (codeUnit == 0x22) {
            inString = false;
          }
          continue;
        }

        if (codeUnit == 0x22) {
          inString = true;
          continue;
        }
        if (codeUnit == 0x7b) {
          depth += 1;
        } else if (codeUnit == 0x7d) {
          depth -= 1;
          if (depth == 0) {
            yield text.substring(start, index + 1);
            break;
          }
        }
      }
    }
  }

  static bool _looksLikeMemoryExtraction(Map<String, dynamic> decoded) {
    return decoded.containsKey('summary') ||
        decoded.containsKey('open_loops') ||
        decoded.containsKey('profile') ||
        decoded.containsKey('memories');
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
  const _JsonCandidate({required this.text, required this.wasRepaired});

  final String text;
  final bool wasRepaired;
}
