import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/session_memory.dart';
import '../repositories/chat_memory_repository.dart';
import '../repositories/conversation_repository.dart';
import 'mcp_client.dart';
import 'searxng_client.dart';

/// MCP tool management service.
///
/// Fetches tools dynamically from an MCP server and executes them.
/// Falls back to SearXNG when the MCP server is unavailable.
class McpToolService {
  McpToolService({
    this.mcpClient,
    this.searxngClient,
    this.conversationRepository,
    this.memoryRepository,
  });

  final McpClient? mcpClient;
  final SearxngClient? searxngClient;
  final ConversationRepository? conversationRepository;
  final ChatMemoryRepository? memoryRepository;

  List<McpToolEntity> _cachedTools = [];
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  String? _lastError;

  /// Current connection status.
  McpConnectionStatus get status => _status;

  /// Cached tool definitions.
  List<McpToolEntity> get tools => _cachedTools;

  /// Most recent error message.
  String? get lastError => _lastError;

  /// Connects to the MCP server and fetches available tools.
  ///
  /// Uses [overrideUrl] for a connection test instead of the saved URL.
  Future<void> connect({String? overrideUrl}) async {
    // Create a temporary client when testing against an override URL.
    final client = overrideUrl != null
        ? McpClient(baseUrl: overrideUrl)
        : mcpClient;

    if (client == null) {
      appLog('[McpToolService] MCP client is null, running in SearXNG mode');
      _status = McpConnectionStatus.disconnected;
      return;
    }

    _status = McpConnectionStatus.connecting;
    _lastError = null;

    try {
      final mcpTools = await client.listTools();
      _cachedTools = mcpTools
          .map(
            (t) => McpToolEntity(
              name: t.name,
              description: t.description,
              inputSchema: t.inputSchema,
            ),
          )
          .toList();
      _status = McpConnectionStatus.connected;
      appLog('[McpToolService] Connected: fetched ${_cachedTools.length} tools');
      for (final tool in _cachedTools) {
        appLog('[McpToolService]   - ${tool.name}: ${tool.description}');
      }
    } catch (e, stackTrace) {
      appLog('[McpToolService] Connection failed: ${e.runtimeType}: $e');
      appLog('[McpToolService] stackTrace: $stackTrace');
      _status = McpConnectionStatus.error;
      _lastError = e.toString();
      _cachedTools = [];
    }
  }

  /// Refreshes the tool list.
  Future<void> refresh() async {
    await connect();
  }

  /// Returns tool definitions for the LLM.
  ///
  /// Returns dynamically fetched tools when MCP is connected.
  /// Otherwise returns the fallback `web_search` tool for SearXNG.
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final toolDefinitions = <Map<String, dynamic>>[_currentDatetimeTool];

    // Built-in memory tools (always available).
    if (conversationRepository != null) {
      toolDefinitions.add(_searchPastConversationsTool);
    }
    if (memoryRepository != null) {
      toolDefinitions.add(_recallMemoryTool);
    }

    // Use MCP tools when connected.
    if (_status == McpConnectionStatus.connected && _cachedTools.isNotEmpty) {
      toolDefinitions.addAll(_cachedTools.map((t) => t.toOpenAiTool()));
      return toolDefinitions;
    }

    // Fallback to the fixed SearXNG tool definition.
    if (searxngClient != null) {
      toolDefinitions.add(_webSearchToolFallback);
    }

    return toolDefinitions;
  }

  /// Executes a tool.
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    appLog('[McpToolService] Executing tool: $name');
    appLog('[McpToolService] Arguments: $arguments');

    // 0. Built-in local tools.
    if (name == 'get_current_datetime') {
      final result = _buildCurrentDatetimeResult();
      appLog('[McpToolService] Local datetime tool executed successfully');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'search_past_conversations' &&
        conversationRepository != null) {
      final result = _searchConversations(arguments);
      appLog('[McpToolService] Conversation search executed: ${result.length} chars');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    if (name == 'recall_memory' && memoryRepository != null) {
      final result = _recallMemory(arguments);
      appLog('[McpToolService] Memory recall executed: ${result.length} chars');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    // 1. Execute through MCP when connected.
    if (_status == McpConnectionStatus.connected && mcpClient != null) {
      // Ensure the requested tool exists.
      final toolExists = _cachedTools.any((t) => t.name == name);
      if (toolExists) {
        try {
          final result = await mcpClient!.callTool(
            name: name,
            arguments: arguments,
          );
          appLog('[McpToolService] MCP execution succeeded: ${result.length} chars');
          return McpToolResult(toolName: name, result: result, isSuccess: true);
        } catch (e) {
          appLog('[McpToolService] MCP tool execution error: $e');
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: e.toString(),
          );
        }
      }
    }

    // 2. SearXNG fallback for `web_search` only.
    if (name == 'web_search' && searxngClient != null) {
      try {
        final query = arguments['query'] as String? ?? '';
        if (query.isEmpty) {
          return McpToolResult(
            toolName: name,
            result: '',
            isSuccess: false,
            errorMessage: 'Search query is empty',
          );
        }
        final result = await searxngClient!.searchAsText(query: query);
        appLog('[McpToolService] SearXNG execution succeeded: ${result.length} chars');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        appLog('[McpToolService] SearXNG error: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    // 3. No matching tool available.
    appLog('[McpToolService] No matching tool available: $name');
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: 'No matching tool available: $name',
    );
  }

  /// Fallback `web_search` tool definition for SearXNG.
  static Map<String, dynamic> get _webSearchToolFallback => {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'Perform a web search on the Internet. Use this to look up the latest information, news, weather, etc.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query'},
        },
        'required': ['query'],
      },
    },
  };

  /// Built-in local datetime tool definition.
  static Map<String, dynamic> get _currentDatetimeTool => {
    'type': 'function',
    'function': {
      'name': 'get_current_datetime',
      'description':
          'Returns the current local date/time and reference date ranges for interpreting relative expressions such as today/this week/recent.',
      'parameters': {'type': 'object', 'properties': {}, 'required': []},
    },
  };

  String _buildCurrentDatetimeResult() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final thisWeekStart = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );
    final thisWeekEnd = thisWeekStart.add(const Duration(days: 6));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = thisWeekEnd.subtract(const Duration(days: 7));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextWeekEnd = thisWeekEnd.add(const Duration(days: 7));
    final recentStart = today.subtract(const Duration(days: 30));

    final payload = <String, dynamic>{
      'local_datetime': _formatDateTime(now),
      'timezone': now.timeZoneName,
      'utc_offset': _formatUtcOffset(now.timeZoneOffset),
      'relative_dates': {
        'today': _formatDate(today),
        'yesterday': _formatDate(yesterday),
        'tomorrow': _formatDate(tomorrow),
        'this_week': {
          'start': _formatDate(thisWeekStart),
          'end': _formatDate(thisWeekEnd),
        },
        'last_week': {
          'start': _formatDate(lastWeekStart),
          'end': _formatDate(lastWeekEnd),
        },
        'next_week': {
          'start': _formatDate(nextWeekStart),
          'end': _formatDate(nextWeekEnd),
        },
        'recent_30_days': {
          'start': _formatDate(recentStart),
          'end': _formatDate(today),
        },
      },
    };

    return jsonEncode(payload);
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateTime(DateTime value) {
    final date = _formatDate(value);
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$date $hour:$minute:$second';
  }

  String _formatUtcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absoluteMinutes = offset.inMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  // ---------------------------------------------------------------------------
  // Built-in tool: search_past_conversations
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _searchPastConversationsTool => {
    'type': 'function',
    'function': {
      'name': 'search_past_conversations',
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

  String _searchConversations(Map<String, dynamic> arguments) {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    final maxResults = ((arguments['max_results'] as num?)?.toInt() ?? 5)
        .clamp(1, 10);
    if (query.isEmpty) return 'Error: search query is empty';

    final conversations = conversationRepository!.getAll();
    final keywords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
    if (keywords.isEmpty) return 'Error: no valid search keywords';

    final matches = <_ConversationMatch>[];
    for (final conversation in conversations) {
      for (final message in conversation.messages) {
        if (message.role == MessageRole.system) continue;
        final content = message.content.toLowerCase();
        final matchCount = keywords.where((kw) => content.contains(kw)).length;
        if (matchCount > 0) {
          matches.add(_ConversationMatch(
            title: conversation.title,
            date: message.timestamp,
            conversationDate: conversation.updatedAt,
            role: message.role.name,
            content: message.content,
            score: matchCount / keywords.length,
          ));
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
      buffer.writeln('${match.role}: ${_truncateText(match.content, 400)}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Built-in tool: recall_memory
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> get _recallMemoryTool => {
    'type': 'function',
    'function': {
      'name': 'recall_memory',
      'description':
          'Search stored memory entries (user preferences, facts, past '
          'topics) for relevant information. Faster than searching full '
          'conversations.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Keywords to search in stored memories',
          },
        },
        'required': ['query'],
      },
    },
  };

  String _recallMemory(Map<String, dynamic> arguments) {
    final query = (arguments['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return 'Error: search query is empty';

    final memories = memoryRepository!.loadMemories();
    if (memories.isEmpty) return 'No memories stored yet.';

    final queryBiGrams = _biGrams(query);
    final scored = <_ScoredMemoryMatch>[];

    for (final memory in memories) {
      if (memory.isExpired) continue;
      final textBiGrams = _biGrams(memory.text);
      if (queryBiGrams.isEmpty || textBiGrams.isEmpty) continue;
      final intersection = queryBiGrams.intersection(textBiGrams).length;
      final union = queryBiGrams.union(textBiGrams).length;
      final similarity = union == 0 ? 0.0 : intersection / union;
      if (similarity > 0.05) {
        scored.add(_ScoredMemoryMatch(memory: memory, score: similarity));
      }
    }

    if (scored.isEmpty) return 'No matching memories found for: $query';

    scored.sort((a, b) => b.score.compareTo(a.score));
    final topMatches = scored.take(5);

    final buffer = StringBuffer();
    for (final match in topMatches) {
      final m = match.memory;
      buffer.writeln(
        '- [${m.type.name}] (confidence: ${m.confidence.toStringAsFixed(2)}) '
        '${m.text} (${_formatDate(m.updatedAt)})',
      );
    }
    return buffer.toString();
  }

  Set<String> _biGrams(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return const {};
    if (normalized.length == 1) return {normalized};
    final grams = <String>{};
    for (var i = 0; i < normalized.length - 1; i++) {
      grams.add(normalized.substring(i, i + 2));
    }
    return grams;
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

class _ConversationMatch {
  _ConversationMatch({
    required this.title,
    required this.date,
    required this.conversationDate,
    required this.role,
    required this.content,
    required this.score,
  });

  final String title;
  final DateTime date;
  final DateTime conversationDate;
  final String role;
  final String content;
  final double score;
}

class _ScoredMemoryMatch {
  _ScoredMemoryMatch({required this.memory, required this.score});

  final MemoryEntry memory;
  final double score;
}
