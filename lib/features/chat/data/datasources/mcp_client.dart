import 'dart:convert';

import 'package:http/http.dart' as http;

class McpClient {
  McpClient({required this.baseUrl});

  final String baseUrl;

  /// MCPセッションID (Streamable HTTP transport)
  String? _sessionId;

  /// セッションIDを取得
  String? get sessionId => _sessionId;

  /// MCPサーバーを初期化してセッションIDを取得
  Future<void> initialize() async {
    print('[McpClient] initialize リクエスト → $baseUrl');
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'openai_chat', 'version': '1.0.0'},
      },
    });
    print('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    print('[McpClient] initialize status: ${httpResp.statusCode}');
    print('[McpClient] initialize headers: ${httpResp.headers}');
    print('[McpClient] initialize body: ${_truncate(body, 500)}');

    if (httpResp.statusCode != 200) {
      print(
        '[McpClient] initialize HTTPエラー: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to initialize MCP: ${httpResp.statusCode}');
    }

    // セッションIDをレスポンスヘッダーから取得
    _sessionId = httpResp.headers['mcp-session-id'];
    print('[McpClient] セッションID: $_sessionId');

    // レスポンス解析
    final json = _decodeJson(body, 'initialize');

    if (json.containsKey('error')) {
      final error = json['error'];
      print('[McpClient] initialize JSON-RPCエラー: $error');
      throw Exception('MCP initialize error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    print('[McpClient] サーバー情報: $result');

    // initialized 通知を送信
    await _sendInitializedNotification();
  }

  /// initialized 通知を送信
  Future<void> _sendInitializedNotification() async {
    print('[McpClient] initialized 通知送信');
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });

    try {
      final (httpResp, _) = await _postRequest(requestBody);
      print('[McpClient] initialized 通知 status: ${httpResp.statusCode}');
    } catch (e) {
      // 通知の失敗は致命的ではない
      print('[McpClient] initialized 通知送信失敗(無視): $e');
    }
  }

  /// MCPサーバーのツール一覧を取得
  Future<List<McpTool>> listTools() async {
    // セッションが未初期化なら初期化
    if (_sessionId == null) {
      await initialize();
    }

    print('[McpClient] listTools リクエスト → $baseUrl');
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    print('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    print('[McpClient] Response status: ${httpResp.statusCode}');
    print('[McpClient] Response headers: ${httpResp.headers}');
    print('[McpClient] Response body (raw): ${_truncate(body, 500)}');

    if (httpResp.statusCode != 200) {
      print(
        '[McpClient] listTools HTTPエラー: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to list tools: ${httpResp.statusCode}');
    }

    final json = _decodeJson(body, 'listTools');

    // JSON-RPCエラーチェック
    if (json.containsKey('error')) {
      final error = json['error'];
      print('[McpClient] listTools JSON-RPCエラー: $error');
      throw Exception('MCP JSON-RPC error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    if (result == null) {
      print('[McpClient] result is null, full response: $json');
      return [];
    }

    final tools = result['tools'] as List<dynamic>? ?? [];
    print('[McpClient] Found ${tools.length} tools');
    return tools
        .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// ツールを実行
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    // セッションが未初期化なら初期化
    if (_sessionId == null) {
      await initialize();
    }

    print('[McpClient] callTool: $name');
    print('[McpClient] arguments: $arguments');

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    });
    print('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    print('[McpClient] Response status: ${httpResp.statusCode}');
    print(
      '[McpClient] Response body (first 500 chars): ${_truncate(body, 500)}',
    );

    if (httpResp.statusCode != 200) {
      print(
        '[McpClient] callTool HTTPエラー: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to call tool: ${httpResp.statusCode}');
    }

    final json = _decodeJson(body, 'callTool');

    // エラーチェック
    if (json.containsKey('error')) {
      final error = json['error'] as Map<String, dynamic>;
      print('[McpClient] Error: ${error['message']}');
      throw Exception('MCP error: ${error['message']}');
    }

    final result = json['result'] as Map<String, dynamic>?;
    if (result == null) {
      print('[McpClient] result is null, full response: $json');
      return '';
    }

    // contentから結果を抽出
    final content = result['content'] as List<dynamic>? ?? [];
    final textContent = content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n');

    print('[McpClient] Result length: ${textContent.length} chars');
    return textContent;
  }

  /// HTTP POSTリクエストを送信（セッションIDヘッダー付き）
  ///
  /// レスポンスのボディはUTF-8で明示的にデコードする。
  /// (http.Responseのbodyはcharset未指定時にLatin-1でデコードされ文字化けするため)
  Future<(http.Response, String)> _postRequest(String body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json, text/event-stream',
    };
    if (_sessionId != null) {
      headers['Mcp-Session-Id'] = _sessionId!;
    }

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: headers,
        body: body,
      );
      final utf8Body = utf8.decode(response.bodyBytes);
      return (response, utf8Body);
    } catch (e, stackTrace) {
      print('[McpClient] HTTP接続エラー: ${e.runtimeType}: $e');
      print('[McpClient] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// JSONデコードのヘルパー（SSE形式のレスポンスにも対応）
  Map<String, dynamic> _decodeJson(String body, String context) {
    try {
      // SSE形式のレスポンスをチェック (event: ... \n data: {...})
      final jsonBody = _extractJsonFromSse(body);
      return jsonDecode(jsonBody) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('[McpClient] $context JSONデコードエラー: ${e.runtimeType}: $e');
      print('[McpClient] Response body: $body');
      print('[McpClient] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// SSE形式のレスポンスからJSONを抽出
  ///
  /// レスポンスが `event: message\ndata: {...}` 形式の場合、
  /// `data:` 行のJSONを結合して返す。通常のJSONはそのまま返す。
  String _extractJsonFromSse(String body) {
    final trimmed = body.trim();
    // 通常のJSONレスポンス（{ または [ で始まる）
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }

    // SSE形式: data: 行を抽出して結合
    print('[McpClient] SSE形式レスポンスを検出、data行を抽出');
    final dataLines = <String>[];
    for (final line in trimmed.split('\n')) {
      if (line.startsWith('data: ')) {
        dataLines.add(line.substring(6)); // 'data: ' の後ろ
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5)); // 'data:' の後ろ（スペースなし）
      }
    }

    if (dataLines.isEmpty) {
      print('[McpClient] SSEレスポンスにdata行がありません: $trimmed');
      throw FormatException('No data lines found in SSE response');
    }

    final jsonStr = dataLines.join('');
    print('[McpClient] SSEから抽出したJSON: ${_truncate(jsonStr, 200)}');
    return jsonStr;
  }

  /// 文字列を指定長に切り詰め
  String _truncate(String s, int maxLen) {
    return s.length > maxLen ? '${s.substring(0, maxLen)}...' : s;
  }
}

class McpTool {
  McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      inputSchema: json['inputSchema'] as Map<String, dynamic>? ?? {},
    );
  }

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// OpenAI形式のツール定義に変換
  Map<String, dynamic> toOpenAiTool() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': inputSchema,
      },
    };
  }
}
