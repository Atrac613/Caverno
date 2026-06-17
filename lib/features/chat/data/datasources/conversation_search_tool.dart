import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// Ranks conversation ids by semantic similarity (LL5), best-first.
typedef SemanticConversationRanker =
    Future<List<String>> Function(String query, int topK);

/// Built-in `search_past_conversations` tool.
///
/// Ranks past conversation messages by keyword overlap. When a
/// [SemanticConversationRanker] is supplied (LL5 semantic search enabled) the
/// conversations it ranks are surfaced first, each shown with its most
/// query-relevant message; otherwise a pure keyword scan is used. Extracted
/// from McpToolService to keep that file within its F1 line budget.
class ConversationSearchTool {
  const ConversationSearchTool();

  static const toolName = 'search_past_conversations';

  static final RegExp _whitespace = RegExp(r'\s+');

  static Map<String, dynamic> get definition => {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Search past conversation history for specific topics, facts, '
          'or information the user discussed previously. Use this when the '
          'user asks about something they mentioned in a past conversation.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search keywords to find in past conversations',
          },
          'max_results': {
            'type': 'integer',
            'description':
                'Maximum number of matching messages to return (default: 5, max: 10)',
          },
        },
        'required': ['query'],
      },
    },
  };

  /// Renders matching past-conversation snippets for the tool [arguments].
  Future<String> run({
    required Map<String, dynamic> arguments,
    required List<Conversation> conversations,
    SemanticConversationRanker? semanticRanker,
  }) async {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    final maxResults = ((arguments['max_results'] as num?)?.toInt() ?? 5).clamp(
      1,
      10,
    );
    if (query.isEmpty) return 'Error: search query is empty';

    final keywords = query
        .toLowerCase()
        .split(_whitespace)
        .where((k) => k.isNotEmpty)
        .toList();
    if (keywords.isEmpty) return 'Error: no valid search keywords';

    if (semanticRanker != null) {
      final ranked = await semanticRanker(query, maxResults);
      if (ranked.isNotEmpty) {
        final byId = {for (final c in conversations) c.id: c};
        final rendered = _renderRanked(ranked, byId, keywords);
        if (rendered != null) return rendered;
      }
    }

    return _keywordSearch(conversations, keywords, query, maxResults);
  }

  String? _renderRanked(
    List<String> rankedIds,
    Map<String, Conversation> byId,
    List<String> keywords,
  ) {
    final buffer = StringBuffer();
    for (final id in rankedIds) {
      final conversation = byId[id];
      if (conversation == null) continue;
      final message = _bestMessage(conversation, keywords);
      if (message == null) continue;
      buffer.writeln(
        '--- [${_formatDate(conversation.updatedAt)}] ${conversation.title} ---',
      );
      buffer.writeln(
        '${message.role.name}: ${_truncate(message.content, 400)}',
      );
      buffer.writeln();
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  /// The message that best matches [keywords], or the first non-empty message.
  Message? _bestMessage(Conversation conversation, List<String> keywords) {
    Message? best;
    var bestScore = 0;
    Message? firstNonEmpty;
    for (final message in conversation.messages) {
      if (message.role == MessageRole.system) continue;
      final content = message.content.trim();
      if (content.isEmpty) continue;
      firstNonEmpty ??= message;
      final lowered = content.toLowerCase();
      final score = keywords.where(lowered.contains).length;
      if (score > bestScore) {
        bestScore = score;
        best = message;
      }
    }
    return best ?? firstNonEmpty;
  }

  String _keywordSearch(
    List<Conversation> conversations,
    List<String> keywords,
    String query,
    int maxResults,
  ) {
    final matches = <_ConversationMatch>[];
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        if (message.role == MessageRole.system) continue;
        final content = message.content.toLowerCase();
        final matchCount = keywords.where(content.contains).length;
        if (matchCount > 0) {
          matches.add(
            _ConversationMatch(
              title: conversation.title,
              conversationDate: conversation.updatedAt,
              role: message.role.name,
              content: message.content,
              score: matchCount / keywords.length,
            ),
          );
        }
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = matches.take(maxResults);
    if (topMatches.isEmpty) {
      return 'No matching conversations found for: $query';
    }

    final buffer = StringBuffer();
    for (final match in topMatches) {
      buffer.writeln(
        '--- [${_formatDate(match.conversationDate)}] ${match.title} ---',
      );
      buffer.writeln('${match.role}: ${_truncate(match.content, 400)}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

class _ConversationMatch {
  _ConversationMatch({
    required this.title,
    required this.conversationDate,
    required this.role,
    required this.content,
    required this.score,
  });

  final String title;
  final DateTime conversationDate;
  final String role;
  final String content;
  final double score;
}
