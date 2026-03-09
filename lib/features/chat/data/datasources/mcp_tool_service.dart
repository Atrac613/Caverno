import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_client.dart';
import 'searxng_client.dart';

/// MCP tool management service.
///
/// Fetches tools dynamically from an MCP server and executes them.
/// Falls back to SearXNG when the MCP server is unavailable.
class McpToolService {
  McpToolService({this.mcpClient, this.searxngClient});

  final McpClient? mcpClient;
  final SearxngClient? searxngClient;

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
      print('[McpToolService] MCPクライアントがnull、SearXNGモードで動作');
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
      print('[McpToolService] 接続成功: ${_cachedTools.length}ツール取得');
      for (final tool in _cachedTools) {
        print('[McpToolService]   - ${tool.name}: ${tool.description}');
      }
    } catch (e, stackTrace) {
      print('[McpToolService] 接続失敗: ${e.runtimeType}: $e');
      print('[McpToolService] stackTrace: $stackTrace');
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
    print('[McpToolService] ツール実行: $name');
    print('[McpToolService] 引数: $arguments');

    // 0. Built-in local tool
    if (name == 'get_current_datetime') {
      final result = _buildCurrentDatetimeResult();
      print('[McpToolService] ローカル日時ツール実行成功');
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
          print('[McpToolService] MCP実行成功: ${result.length} chars');
          return McpToolResult(toolName: name, result: result, isSuccess: true);
        } catch (e) {
          print('[McpToolService] MCPツール実行エラー: $e');
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
            errorMessage: '検索クエリが空です',
          );
        }
        final result = await searxngClient!.searchAsText(query: query);
        print('[McpToolService] SearXNG実行成功: ${result.length} chars');
        return McpToolResult(toolName: name, result: result, isSuccess: true);
      } catch (e) {
        print('[McpToolService] SearXNGエラー: $e');
        return McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: e.toString(),
        );
      }
    }

    // 3. No matching tool available.
    print('[McpToolService] 対応するツールがありません: $name');
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: '対応するツールがありません: $name',
    );
  }

  /// Fallback `web_search` tool definition for SearXNG.
  static Map<String, dynamic> get _webSearchToolFallback => {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': 'インターネットでWeb検索を実行します。最新の情報、ニュース、天気などを調べる際に使用してください。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '検索クエリ'},
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
          '現在のローカル日時と、today/this week/recent などの相対表現を解釈するための基準日付レンジを返します。',
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
}
