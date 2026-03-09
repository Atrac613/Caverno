import 'dart:convert';

import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_client.dart';
import 'searxng_client.dart';

/// MCPツール管理サービス
///
/// MCPサーバーからツールを動的に取得し、実行する。
/// MCPサーバーが利用できない場合はSearXNGにフォールバック。
class McpToolService {
  McpToolService({this.mcpClient, this.searxngClient});

  final McpClient? mcpClient;
  final SearxngClient? searxngClient;

  List<McpToolEntity> _cachedTools = [];
  McpConnectionStatus _status = McpConnectionStatus.disconnected;
  String? _lastError;

  /// 接続状態
  McpConnectionStatus get status => _status;

  /// キャッシュされたツール一覧
  List<McpToolEntity> get tools => _cachedTools;

  /// 最後のエラーメッセージ
  String? get lastError => _lastError;

  /// MCPサーバーに接続してツール一覧を取得
  ///
  /// [overrideUrl] を指定すると、保存済み設定のURLではなくそのURLで接続テストを行う。
  Future<void> connect({String? overrideUrl}) async {
    // overrideUrlが指定された場合は一時的なMcpClientを作成
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

  /// ツール一覧を再取得
  Future<void> refresh() async {
    await connect();
  }

  /// LLM用ツール定義を取得
  ///
  /// MCP接続済みの場合は動的に取得したツールを返す。
  /// そうでない場合はSearXNG用のweb_searchツールを返す。
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final toolDefinitions = <Map<String, dynamic>>[_currentDatetimeTool];

    // MCP接続済みでツールがある場合
    if (_status == McpConnectionStatus.connected && _cachedTools.isNotEmpty) {
      toolDefinitions.addAll(_cachedTools.map((t) => t.toOpenAiTool()));
      return toolDefinitions;
    }

    // フォールバック: SearXNG用の固定ツール
    if (searxngClient != null) {
      toolDefinitions.add(_webSearchToolFallback);
    }

    return toolDefinitions;
  }

  /// ツールを実行
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    print('[McpToolService] ツール実行: $name');
    print('[McpToolService] 引数: $arguments');

    // 0. ローカルツール
    if (name == 'get_current_datetime') {
      final result = _buildCurrentDatetimeResult();
      print('[McpToolService] ローカル日時ツール実行成功');
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    }

    // 1. MCP接続中ならMCPで実行
    if (_status == McpConnectionStatus.connected && mcpClient != null) {
      // ツールが存在するか確認
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

    // 2. SearXNGフォールバック（web_searchのみ）
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

    // 3. 対応ツールなし
    print('[McpToolService] 対応するツールがありません: $name');
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: '対応するツールがありません: $name',
    );
  }

  /// SearXNGフォールバック用のweb_searchツール定義
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

  /// ローカル日時ツール定義
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
