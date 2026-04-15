import 'dart:convert';

/// Content segment types
enum ContentType { text, thinking, toolCall, toolResult }

/// Tool call data
class ToolCallData {
  final String name;
  final Map<String, dynamic> arguments;
  final bool isComplete;
  final String? occurrenceId;

  const ToolCallData({
    required this.name,
    required this.arguments,
    this.isComplete = false,
    this.occurrenceId,
  });

  @override
  String toString() =>
      'ToolCallData(name: $name, arguments: $arguments, occurrenceId: $occurrenceId)';
}

/// Content segment
class ContentSegment {
  final ContentType type;
  final String content;
  final ToolCallData? toolCall;

  const ContentSegment({
    required this.type,
    required this.content,
    this.toolCall,
  });

  @override
  String toString() =>
      'ContentSegment(type: $type, content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
}

/// Parse result
class ParseResult {
  final List<ContentSegment> segments;
  final bool hasIncompleteTag;
  final String? incompleteTagType;
  final String? incompleteTagContent;

  const ParseResult({
    required this.segments,
    this.hasIncompleteTag = false,
    this.incompleteTagType,
    this.incompleteTagContent,
  });
}

/// Content parser
/// Parses `\<think>` and `\<tool_call>` tags in LLM responses.
class ContentParser {
  static final _modelControlTokenPattern = RegExp(
    r'<(?:\|/?[a-zA-Z_][a-zA-Z0-9_-]*\|?|/?[a-zA-Z_][a-zA-Z0-9_-]*\|)>',
  );

  static final _structuralTagPattern = RegExp(
    r'(?:</?(?:think|thinking|thought|tool_call|tool_use|tool_result)>|<\|/?(?:think|thinking|thought|tool_call|tool_use|tool_result|end_tool_call|end_tool_use)\|?>)',
  );

  // Regex to detect complete tags
  static final _thinkPattern = RegExp(
    r'<(think|thinking|thought)>(.*?)</(think|thinking|thought)>',
    dotAll: true,
  );

  static final _toolCallPattern = RegExp(
    r'(?:<tool_call>|<\|tool_call\|?>)(.*?)(?:</tool_call>|<\|/tool_call\|?>|<\|end_tool_call\|?>)',
    dotAll: true,
  );

  static final _toolUsePattern = RegExp(
    r'(?:<tool_use>|<\|tool_use\|?>)(.*?)(?:</tool_use>|<\|/tool_use\|?>|<\|end_tool_use\|?>)',
    dotAll: true,
  );

  static final _toolResultPattern = RegExp(
    r'<tool_result>(.*?)</tool_result>',
    dotAll: true,
  );

  // Patterns to detect incomplete tags
  static final _incompleteThinkStart = RegExp(
    r'<(think|thinking|thought)>(?!.*</(think|thinking|thought)>).*$',
    dotAll: true,
  );

  static final _incompleteToolCallStart = RegExp(
    r'(?:<tool_call>|<\|tool_call\|?>)(?!.*(?:</tool_call>|<\|/tool_call\|?>|<\|end_tool_call\|?>)).*$',
    dotAll: true,
  );

  static final _incompleteToolUseStart = RegExp(
    r'(?:<tool_use>|<\|tool_use\|?>)(?!.*(?:</tool_use>|<\|/tool_use\|?>|<\|end_tool_use\|?>)).*$',
    dotAll: true,
  );

  static final _controlToolCallUntilEndPattern = RegExp(
    r'<\|tool_(?:call|use)\|?>(.*?)(?=<\|(?:/?[a-zA-Z_][a-zA-Z0-9_-]*|end_tool_(?:call|use))\|?>|$)',
    dotAll: true,
  );

  static final _bareToolCallPrefixPattern = RegExp(
    r'call\s*:\s*([a-zA-Z_][a-zA-Z0-9_-]*)\s*\{',
  );

  // Partial tag (unclosed <)
  static final _partialTagPattern = RegExp(r'<[^>]*$');

  /// Parse content into segments
  static ParseResult parse(String content) {
    if (content.isEmpty) {
      return const ParseResult(segments: []);
    }

    final segments = <ContentSegment>[];
    var remaining = content;
    var hasIncompleteTag = false;
    String? incompleteTagType;

    // Check for incomplete tags
    if (_incompleteThinkStart.hasMatch(remaining)) {
      hasIncompleteTag = true;
      incompleteTagType = 'thinking';
    } else if (_incompleteToolCallStart.hasMatch(remaining)) {
      hasIncompleteTag = true;
      incompleteTagType = 'tool_call';
    } else if (_incompleteToolUseStart.hasMatch(remaining)) {
      hasIncompleteTag = true;
      incompleteTagType = 'tool_call';
    } else if (_findBareToolCallStart(remaining) case final bareStart?
        when !_hasCompleteBareToolCall(remaining, bareStart)) {
      hasIncompleteTag = true;
      incompleteTagType = 'tool_call';
    } else if (_partialTagPattern.hasMatch(remaining)) {
      hasIncompleteTag = true;
      incompleteTagType = 'partial';
    }

    // Collect all tag positions
    final allMatches = <_TagMatch>[];

    // Collect think tags
    for (final match in _thinkPattern.allMatches(content)) {
      allMatches.add(
        _TagMatch(
          start: match.start,
          end: match.end,
          type: ContentType.thinking,
          innerContent: match.group(2) ?? '',
        ),
      );
    }

    // Collect tool_call tags
    for (final match in _toolCallPattern.allMatches(content)) {
      allMatches.add(
        _TagMatch(
          start: match.start,
          end: match.end,
          type: ContentType.toolCall,
          innerContent: match.group(1) ?? '',
        ),
      );
    }

    // Collect tool_use tags (display only)
    for (final match in _toolUsePattern.allMatches(content)) {
      allMatches.add(
        _TagMatch(
          start: match.start,
          end: match.end,
          type: ContentType.toolCall,
          innerContent: match.group(1) ?? '',
        ),
      );
    }

    for (final match in _extractBareToolCallMatches(content, allMatches)) {
      allMatches.add(match);
    }

    // Collect tool_result tags (display only)
    for (final match in _toolResultPattern.allMatches(content)) {
      allMatches.add(
        _TagMatch(
          start: match.start,
          end: match.end,
          type: ContentType.toolResult,
          innerContent: match.group(1) ?? '',
        ),
      );
    }

    // Sort by start position
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // Build segments
    var currentPos = 0;
    for (final match in allMatches) {
      // Add text before the tag if present
      if (match.start > currentPos) {
        final textBefore = _sanitizeDisplayText(
          content.substring(currentPos, match.start),
        );
        if (textBefore.trim().isNotEmpty) {
          segments.add(
            ContentSegment(type: ContentType.text, content: textBefore),
          );
        }
      }

      // Add the tag content
      if (match.type == ContentType.thinking) {
        segments.add(
          ContentSegment(
            type: ContentType.thinking,
            content: _sanitizeDisplayText(match.innerContent).trim(),
          ),
        );
      } else if (match.type == ContentType.toolCall) {
        final toolCall = _parseToolCallContent(match.innerContent);
        segments.add(
          ContentSegment(
            type: ContentType.toolCall,
            content: match.innerContent,
            toolCall: toolCall,
          ),
        );
      } else if (match.type == ContentType.toolResult) {
        final toolResult = _parseToolCallContent(match.innerContent);
        segments.add(
          ContentSegment(
            type: ContentType.toolResult,
            content: match.innerContent,
            toolCall: toolResult,
          ),
        );
      }

      currentPos = match.end;
    }

    // Add remaining text if any (excluding incomplete tags)
    String? capturedIncompleteContent;

    if (currentPos < content.length) {
      var remainingText = content.substring(currentPos);

      // Remove incomplete tags and capture partial thinking content
      if (hasIncompleteTag) {
        if (incompleteTagType == 'thinking') {
          final match = _incompleteThinkStart.firstMatch(remainingText);
          if (match != null) {
            // Extract partial thinking content after the opening tag
            final fullMatch = match.group(0) ?? '';
            final tagNameMatch = RegExp(
              r'^<(think|thinking|thought)>',
            ).firstMatch(fullMatch);
            if (tagNameMatch != null) {
              capturedIncompleteContent = fullMatch
                  .substring(tagNameMatch.end)
                  .trim();
            }
            remainingText = remainingText.substring(0, match.start);
          }
        } else if (incompleteTagType == 'tool_call') {
          final match = _incompleteToolCallStart.firstMatch(remainingText);
          if (match != null) {
            remainingText = remainingText.substring(0, match.start);
          } else {
            final toolUseMatch = _incompleteToolUseStart.firstMatch(
              remainingText,
            );
            if (toolUseMatch != null) {
              remainingText = remainingText.substring(0, toolUseMatch.start);
            } else if (_findBareToolCallStart(remainingText)
                case final bareStart?) {
              remainingText = remainingText.substring(0, bareStart);
            }
          }
        } else if (incompleteTagType == 'partial') {
          final match = _partialTagPattern.firstMatch(remainingText);
          if (match != null) {
            remainingText = remainingText.substring(0, match.start);
          }
        }
      }

      final sanitizedRemainingText = _sanitizeDisplayText(remainingText);
      if (sanitizedRemainingText.trim().isNotEmpty) {
        segments.add(
          ContentSegment(
            type: ContentType.text,
            content: sanitizedRemainingText,
          ),
        );
      }
    }

    return ParseResult(
      segments: segments,
      hasIncompleteTag: hasIncompleteTag,
      incompleteTagType: incompleteTagType,
      incompleteTagContent: capturedIncompleteContent == null
          ? null
          : _sanitizeDisplayText(capturedIncompleteContent),
    );
  }

  /// Extracts completed `\<tool_call>` and `\<tool_use>` entries.
  static List<ToolCallData> extractCompletedToolCalls(String content) {
    final toolCalls = <ToolCallData>[];

    final matches =
        [
              ..._toolCallPattern.allMatches(content),
              ..._toolUsePattern.allMatches(content),
              ..._controlToolCallUntilEndPattern.allMatches(content),
            ]
            .map(
              (match) => _TagMatch(
                start: match.start,
                end: match.end,
                type: ContentType.toolCall,
                innerContent: match.group(1) ?? '',
              ),
            )
            .toList();

    matches.addAll(_extractBareToolCallMatches(content, matches));
    matches.sort((a, b) => a.start.compareTo(b.start));

    for (final match in matches) {
      final innerContent = match.innerContent;
      final parsed = _parseToolCallContent(innerContent);
      if (parsed != null && parsed.name != 'memory_update') {
        toolCalls.add(
          ToolCallData(
            name: parsed.name,
            arguments: parsed.arguments,
            isComplete: true,
            occurrenceId: '${match.start}:${match.end}',
          ),
        );
      }
    }

    return toolCalls;
  }

  /// Parse tool_call content
  static ToolCallData? _parseToolCallContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    try {
      // Try JSON format
      // {"name": "web_search", "arguments": {"query": "..."}}
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final name = json['name'] as String?;
      final arguments = json['arguments'] as Map<String, dynamic>?;

      if (name != null) {
        final flattenedArguments = <String, dynamic>{};
        for (final entry in json.entries) {
          if (entry.key == 'name' || entry.key == 'arguments') {
            continue;
          }
          flattenedArguments[entry.key] = entry.value;
        }

        return ToolCallData(
          name: name,
          arguments: arguments ?? flattenedArguments,
          isComplete: true,
        );
      }
    } catch (_) {
      // JSON parse failed - try other formats
    }

    final controlCallMatch = RegExp(
      r'^call\s*:\s*([a-zA-Z_][a-zA-Z0-9_-]*)\s*(\{.*\})$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (controlCallMatch != null) {
      final name = controlCallMatch.group(1)!;
      final objectLiteral = controlCallMatch.group(2)!;
      final arguments = _parseLooseObjectLiteral(objectLiteral);
      if (arguments != null) {
        return ToolCallData(name: name, arguments: arguments, isComplete: true);
      }
    }

    // XML format: tool_name\n<arg_key>key</arg_key>\n<arg_value>value</arg_value>
    // e.g.: web_search\n<arg_key>query</arg_key>\n<arg_value>search query</arg_value>
    final xmlArgPattern = RegExp(
      r'^(\w+)\s*[\n\r]+<arg_key>(\w+)</arg_key>\s*[\n\r]*<arg_value>(.+?)</arg_value>',
      dotAll: true,
    );
    final xmlMatch = xmlArgPattern.firstMatch(trimmed);
    if (xmlMatch != null) {
      final name = xmlMatch.group(1)!;
      final argKey = xmlMatch.group(2)!;
      final argValue = xmlMatch.group(3)!.trim();
      return ToolCallData(
        name: name,
        arguments: {argKey: argValue},
        isComplete: true,
      );
    }

    // Try simple format
    // web_search("query")
    final simpleMatch = RegExp(
      r'(\w+)\s*\(\s*"([^"]+)"\s*\)',
    ).firstMatch(trimmed);
    if (simpleMatch != null) {
      return ToolCallData(
        name: simpleMatch.group(1)!,
        arguments: {'query': simpleMatch.group(2)},
        isComplete: true,
      );
    }

    // name: xxx, query: xxx format
    final nameMatch = RegExp(
      r'name\s*[:=]\s*["\x27]?(\w+)["\x27]?',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final queryMatch = RegExp(
      r'query\s*[:=]\s*["\x27]?([^"\x27]+)["\x27]?',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (nameMatch != null) {
      return ToolCallData(
        name: nameMatch.group(1)!,
        arguments: queryMatch != null
            ? {'query': queryMatch.group(1)!.trim()}
            : {},
        isComplete: true,
      );
    }

    // Simple format: first line is tool name, rest is arguments
    // e.g.: web_search\nquery text here
    final lines = trimmed.split(RegExp(r'[\n\r]+'));
    if (lines.length >= 2) {
      final possibleName = lines[0].trim();
      if (RegExp(r'^\w+$').hasMatch(possibleName)) {
        final queryText = lines.skip(1).join(' ').trim();
        if (queryText.isNotEmpty) {
          return ToolCallData(
            name: possibleName,
            arguments: {'query': queryText},
            isComplete: true,
          );
        }
      }
    }

    return null;
  }

  static String _sanitizeDisplayText(String text) {
    return text
        .replaceAll(_modelControlTokenPattern, '')
        .replaceAll(_structuralTagPattern, '');
  }

  static Map<String, dynamic>? _parseLooseObjectLiteral(String source) {
    final trimmed = source.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall through to a normalized retry.
    }

    final normalized = trimmed.replaceAllMapped(
      RegExp(r'([{\s,])([a-zA-Z_][a-zA-Z0-9_-]*)(\s*:)'),
      (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
    );

    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // Fall through to the manual parser.
    }

    final result = <String, dynamic>{};
    var index = 1;
    while (index < trimmed.length - 1) {
      index = _skipWhitespaceAndCommas(trimmed, index);
      if (index >= trimmed.length - 1) {
        break;
      }

      final keyToken = _readLooseKey(trimmed, index);
      if (keyToken == null) return null;
      final key = keyToken.value;
      index = _skipWhitespace(trimmed, keyToken.nextIndex);
      if (index >= trimmed.length || trimmed[index] != ':') return null;
      index = _skipWhitespace(trimmed, index + 1);

      final valueToken = _readLooseValue(trimmed, index);
      if (valueToken == null) return null;
      result[key] = valueToken.value;
      index = _skipWhitespace(trimmed, valueToken.nextIndex);

      if (index < trimmed.length - 1 && trimmed[index] != ',') {
        return null;
      }
      if (index < trimmed.length - 1 && trimmed[index] == ',') {
        index += 1;
      }
    }

    return result;
  }

  static List<_TagMatch> _extractBareToolCallMatches(
    String content,
    List<_TagMatch> existingMatches,
  ) {
    final matches = <_TagMatch>[];
    for (final prefixMatch in _bareToolCallPrefixPattern.allMatches(content)) {
      if (_overlapsExistingMatch(prefixMatch.start, prefixMatch.end, [
        ...existingMatches,
        ...matches,
      ])) {
        continue;
      }

      final braceStart = content.indexOf('{', prefixMatch.start);
      if (braceStart < 0) continue;
      final braceEnd = _findLooseObjectEnd(content, braceStart);
      if (braceEnd == null || !_onlyWhitespaceAfter(content, braceEnd + 1)) {
        continue;
      }

      matches.add(
        _TagMatch(
          start: prefixMatch.start,
          end: braceEnd + 1,
          type: ContentType.toolCall,
          innerContent: content.substring(prefixMatch.start, braceEnd + 1),
        ),
      );
    }
    return matches;
  }

  static bool _overlapsExistingMatch(
    int start,
    int end,
    List<_TagMatch> matches,
  ) {
    for (final match in matches) {
      if (start < match.end && end > match.start) {
        return true;
      }
    }
    return false;
  }

  static int? _findBareToolCallStart(String content) {
    final match = _bareToolCallPrefixPattern.firstMatch(content);
    return match?.start;
  }

  static bool _hasCompleteBareToolCall(String content, int start) {
    final braceStart = content.indexOf('{', start);
    if (braceStart < 0) return false;
    final braceEnd = _findLooseObjectEnd(content, braceStart);
    return braceEnd != null && _onlyWhitespaceAfter(content, braceEnd + 1);
  }

  static bool _onlyWhitespaceAfter(String content, int index) {
    return content.substring(index).trim().isEmpty;
  }

  static int _skipWhitespace(String source, int index) {
    while (index < source.length && RegExp(r'\s').hasMatch(source[index])) {
      index += 1;
    }
    return index;
  }

  static int _skipWhitespaceAndCommas(String source, int index) {
    while (index < source.length) {
      final char = source[index];
      if (char == ',' || RegExp(r'\s').hasMatch(char)) {
        index += 1;
        continue;
      }
      break;
    }
    return index;
  }

  static _LooseToken<String>? _readLooseKey(String source, int index) {
    if (index >= source.length) return null;
    final char = source[index];
    if (char == '"' || char == "'") {
      final end = _findLooseStringEnd(source, index);
      if (end == null) return null;
      return _LooseToken(source.substring(index + 1, end), end + 1);
    }

    final match = RegExp(
      r'[a-zA-Z_][a-zA-Z0-9_-]*',
    ).matchAsPrefix(source, index);
    if (match == null) return null;
    return _LooseToken(match.group(0)!, match.end);
  }

  static _LooseToken<dynamic>? _readLooseValue(String source, int index) {
    if (index >= source.length) return null;
    final char = source[index];

    if (char == '"' || char == "'") {
      final end = _findLooseStringEnd(source, index);
      if (end == null) return null;
      return _LooseToken(source.substring(index + 1, end), end + 1);
    }

    if (char == '{') {
      final end = _findLooseObjectEnd(source, index);
      if (end == null) return null;
      final objectValue = _parseLooseObjectLiteral(
        source.substring(index, end + 1),
      );
      return _LooseToken(objectValue, end + 1);
    }

    if (char == '[') {
      final end = _findLooseBracketEnd(source, index, '[', ']');
      if (end == null) return null;
      final raw = source.substring(index, end + 1);
      try {
        return _LooseToken(jsonDecode(raw), end + 1);
      } catch (_) {
        return _LooseToken(raw, end + 1);
      }
    }

    var end = index;
    while (end < source.length && source[end] != ',' && source[end] != '}') {
      end += 1;
    }
    final raw = source.substring(index, end).trim();
    if (raw.isEmpty) return null;
    if (raw == 'true') return _LooseToken(true, end);
    if (raw == 'false') return _LooseToken(false, end);
    if (raw == 'null') return _LooseToken(null, end);
    final numeric = num.tryParse(raw);
    if (numeric != null) return _LooseToken(numeric, end);
    return _LooseToken(raw, end);
  }

  static int? _findLooseObjectEnd(String source, int openBraceIndex) {
    return _findLooseBracketEnd(source, openBraceIndex, '{', '}');
  }

  static int? _findLooseBracketEnd(
    String source,
    int startIndex,
    String openChar,
    String closeChar,
  ) {
    var depth = 0;
    var index = startIndex;

    while (index < source.length) {
      final char = source[index];
      if (char == '"' || char == "'") {
        final stringEnd = _findLooseStringEnd(source, index);
        if (stringEnd == null) return null;
        index = stringEnd + 1;
        continue;
      }
      if (char == openChar) {
        depth += 1;
      } else if (char == closeChar) {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
      index += 1;
    }

    return null;
  }

  static int? _findLooseStringEnd(String source, int startIndex) {
    if (startIndex >= source.length) return null;
    final quote = source[startIndex];
    var index = startIndex + 1;

    while (index < source.length) {
      final char = source[index];
      if (char == r'\') {
        index += 2;
        continue;
      }
      if (char == quote) {
        final nextIndex = _skipWhitespace(source, index + 1);
        if (nextIndex >= source.length) {
          return index;
        }
        final nextChar = source[nextIndex];
        if (nextChar == ',' ||
            nextChar == '}' ||
            nextChar == ']' ||
            nextChar == ':') {
          return index;
        }
      }
      index += 1;
    }

    return null;
  }
}

/// Internal class for tag match
class _TagMatch {
  final int start;
  final int end;
  final ContentType type;
  final String innerContent;

  _TagMatch({
    required this.start,
    required this.end,
    required this.type,
    required this.innerContent,
  });
}

class _LooseToken<T> {
  final T value;
  final int nextIndex;

  const _LooseToken(this.value, this.nextIndex);
}
