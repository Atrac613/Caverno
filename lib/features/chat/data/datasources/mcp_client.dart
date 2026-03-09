import 'dart:convert';

import 'package:http/http.dart' as http;

class McpClient {
  McpClient({required this.baseUrl});

  final String baseUrl;

  /// MCP session ID for the streamable HTTP transport.
  String? _sessionId;

  /// Returns the current session ID.
  String? get sessionId => _sessionId;

  /// Initializes the MCP server and stores the session ID.
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

    // Read the session ID from the response headers.
    _sessionId = httpResp.headers['mcp-session-id'];
    print('[McpClient] セッションID: $_sessionId');

    // Parse the response payload.
    final json = _decodeJson(body, 'initialize');

    if (json.containsKey('error')) {
      final error = json['error'];
      print('[McpClient] initialize JSON-RPCエラー: $error');
      throw Exception('MCP initialize error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    print('[McpClient] サーバー情報: $result');

    // Send the initialized notification.
    await _sendInitializedNotification();
  }

  /// Sends the initialized notification.
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
      // Notification failures are non-fatal.
      print('[McpClient] initialized 通知送信失敗(無視): $e');
    }
  }

  /// Fetches the tool list from the MCP server.
  Future<List<McpTool>> listTools() async {
    // Initialize the session on first use.
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

    // Check for JSON-RPC errors.
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

  /// Executes a tool.
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    // Initialize the session on first use.
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

    // Check for errors in the response.
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

    // Extract text results from the content array.
    final content = result['content'] as List<dynamic>? ?? [];
    final textContent = content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n');

    print('[McpClient] Result length: ${textContent.length} chars');
    return textContent;
  }

  /// Sends an HTTP POST request with the session ID header when available.
  ///
  /// Explicitly decodes the response body as UTF-8.
  /// `http.Response.body` falls back to Latin-1 when no charset is provided.
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

  /// Helper for JSON decoding, including SSE-style responses.
  Map<String, dynamic> _decodeJson(String body, String context) {
    try {
      // Handle SSE-style payloads such as `event: ...` and `data: {...}`.
      final jsonBody = _extractJsonFromSse(body);
      return jsonDecode(jsonBody) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('[McpClient] $context JSONデコードエラー: ${e.runtimeType}: $e');
      print('[McpClient] Response body: $body');
      print('[McpClient] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Extracts JSON from an SSE-style response body.
  ///
  /// When the response is `event: message\ndata: {...}`, this joins the
  /// `data:` lines and returns them as JSON. Plain JSON is returned as-is.
  String _extractJsonFromSse(String body) {
    final trimmed = body.trim();
    // Return plain JSON responses unchanged.
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return trimmed;
    }

    // Extract and join `data:` lines from SSE responses.
    print('[McpClient] SSE形式レスポンスを検出、data行を抽出');
    final dataLines = <String>[];
    for (final line in trimmed.split('\n')) {
      if (line.startsWith('data: ')) {
        dataLines.add(line.substring(6)); // Content after `data: `
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5)); // Content after `data:` with no space
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

  /// Truncates a string to the requested length.
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

  /// Converts the tool definition to the OpenAI tool format.
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
