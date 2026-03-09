import 'dart:convert';

/// コンテンツセグメントの種類
enum ContentType { text, thinking, toolCall }

/// ツール呼び出しデータ
class ToolCallData {
  final String name;
  final Map<String, dynamic> arguments;
  final bool isComplete;

  const ToolCallData({
    required this.name,
    required this.arguments,
    this.isComplete = false,
  });

  @override
  String toString() => 'ToolCallData(name: $name, arguments: $arguments)';
}

/// コンテンツセグメント
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

/// 解析結果
class ParseResult {
  final List<ContentSegment> segments;
  final bool hasIncompleteTag;
  final String? incompleteTagType;

  const ParseResult({
    required this.segments,
    this.hasIncompleteTag = false,
    this.incompleteTagType,
  });
}

/// コンテンツパーサー
/// LLM応答に含まれる<think>や<tool_call>タグを解析する
class ContentParser {
  // 完全なタグを検出するRegex
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

  // 不完全なタグを検出するパターン
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

  // 部分的なタグ（閉じていない < ）
  static final _partialTagPattern = RegExp(r'<[^>]*$');

  /// コンテンツを解析してセグメントに分割
  static ParseResult parse(String content) {
    if (content.isEmpty) {
      return const ParseResult(segments: []);
    }

    final segments = <ContentSegment>[];
    var remaining = content;
    var hasIncompleteTag = false;
    String? incompleteTagType;

    // 不完全なタグをチェック
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

    // すべてのタグの位置を収集
    final allMatches = <_TagMatch>[];

    // thinkタグを収集
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

    // tool_callタグを収集
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

    // tool_useタグを収集（表示専用）
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

    // 開始位置でソート
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    // セグメントを構築
    var currentPos = 0;
    for (final match in allMatches) {
      // タグの前のテキストがあれば追加
      if (match.start > currentPos) {
        final textBefore = content.substring(currentPos, match.start);
        if (textBefore.trim().isNotEmpty) {
          segments.add(
            ContentSegment(type: ContentType.text, content: textBefore),
          );
        }
      }

      // タグの内容を追加
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

    // 残りのテキストがあれば追加（不完全なタグは除く）
    if (currentPos < content.length) {
      var remainingText = content.substring(currentPos);

      // 不完全なタグを除去
      if (hasIncompleteTag) {
        if (incompleteTagType == 'thinking') {
          final match = _incompleteThinkStart.firstMatch(remainingText);
          if (match != null) {
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
    );
  }

  /// 完了した<tool_call>を抽出
  static List<ToolCallData> extractCompletedToolCalls(String content) {
    final toolCalls = <ToolCallData>[];

    for (final match in _toolCallPattern.allMatches(content)) {
      final innerContent = match.group(1) ?? '';
      final parsed = _parseToolCallContent(innerContent);
      if (parsed != null) {
        toolCalls.add(
          ToolCallData(
            name: parsed.name,
            arguments: parsed.arguments,
            isComplete: true,
          ),
        );
      }
    }

    return toolCalls;
  }

  /// tool_callの内容をパース
  static ToolCallData? _parseToolCallContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    try {
      // JSON形式を試す
      // {"name": "web_search", "arguments": {"query": "..."}}
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final name = json['name'] as String?;
      final arguments = json['arguments'] as Map<String, dynamic>?;

      if (name != null) {
        return ToolCallData(
          name: name,
          arguments: arguments ?? {},
          isComplete: true,
        );
      }
    } catch (_) {
      // JSONパース失敗 - 別のフォーマットを試す
    }

    // XML形式: tool_name\n<arg_key>key</arg_key>\n<arg_value>value</arg_value>
    // 例: web_search\n<arg_key>query</arg_key>\n<arg_value>検索クエリ</arg_value>
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

    // シンプルなフォーマットを試す
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

    // name: xxx, query: xxx 形式
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

    // 最初の行がツール名、残りが引数のシンプル形式
    // 例: web_search\nquery text here
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

/// タグマッチの内部クラス
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
