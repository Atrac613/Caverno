import 'dart:convert';

/// Content segment types
enum ContentType { text, thinking, toolCall }

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
  // Regex to detect complete tags
  static final _thinkPattern = RegExp(
    r'<(think|thinking)>(.*?)</(think|thinking)>',
    dotAll: true,
  );

  static final _toolCallPattern = RegExp(
    r'<tool_call>(.*?)</tool_call>',
    dotAll: true,
  );

  static final _toolUsePattern = RegExp(
    r'<tool_use>(.*?)</tool_use>',
    dotAll: true,
  );

  // Patterns to detect incomplete tags
  static final _incompleteThinkStart = RegExp(
    r'<(think|thinking)>(?!.*</(think|thinking)>).*$',
    dotAll: true,
  );

  static final _incompleteToolCallStart = RegExp(
    r'<tool_call>(?!.*</tool_call>).*$',
    dotAll: true,
  );

  static final _incompleteToolUseStart = RegExp(
    r'<tool_use>(?!.*</tool_use>).*$',
    dotAll: true,
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

    // Sort by start position
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // Build segments
    var currentPos = 0;
    for (final match in allMatches) {
      // Add text before the tag if present
      if (match.start > currentPos) {
        final textBefore = content.substring(currentPos, match.start);
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
            content: match.innerContent.trim(),
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
              r'^<(think|thinking)>',
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
            }
          }
        } else if (incompleteTagType == 'partial') {
          final match = _partialTagPattern.firstMatch(remainingText);
          if (match != null) {
            remainingText = remainingText.substring(0, match.start);
          }
        }
      }

      if (remainingText.trim().isNotEmpty) {
        segments.add(
          ContentSegment(type: ContentType.text, content: remainingText),
        );
      }
    }

    return ParseResult(
      segments: segments,
      hasIncompleteTag: hasIncompleteTag,
      incompleteTagType: incompleteTagType,
      incompleteTagContent: capturedIncompleteContent,
    );
  }

  /// Extracts completed `\<tool_call>` and `\<tool_use>` entries.
  static List<ToolCallData> extractCompletedToolCalls(String content) {
    final toolCalls = <ToolCallData>[];

    final matches = [
      ..._toolCallPattern.allMatches(content),
      ..._toolUsePattern.allMatches(content),
    ]..sort((a, b) => a.start.compareTo(b.start));

    for (final match in matches) {
      final innerContent = match.group(1) ?? '';
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
