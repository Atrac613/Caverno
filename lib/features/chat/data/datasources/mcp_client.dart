import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/utils/logger.dart';

class McpClient {
  McpClient({required this.baseUrl});

  final String baseUrl;

  /// MCP session ID for the streamable HTTP transport.
  String? _sessionId;

  /// Returns the current session ID.
  String? get sessionId => _sessionId;

  /// Initializes the MCP server and stores the session ID.
  Future<void> initialize() async {
    appLog('[McpClient] initialize request → $baseUrl');
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
    appLog('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    appLog('[McpClient] initialize status: ${httpResp.statusCode}');
    appLog('[McpClient] initialize headers: ${httpResp.headers}');
    appLog('[McpClient] initialize body: ${_truncate(body, 500)}');

    if (httpResp.statusCode != 200) {
      appLog(
        '[McpClient] initialize HTTP error: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to initialize MCP: ${httpResp.statusCode}');
    }

    // Read the session ID from the response headers.
    _sessionId = httpResp.headers['mcp-session-id'];
    appLog('[McpClient] Session ID: $_sessionId');

    // Parse the response payload.
    final json = _decodeJson(body, 'initialize');

    if (json.containsKey('error')) {
      final error = json['error'];
      appLog('[McpClient] initialize JSON-RPC error: $error');
      throw Exception('MCP initialize error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    appLog('[McpClient] Server info: $result');

    // Send the initialized notification.
    await _sendInitializedNotification();
  }

  /// Sends the initialized notification.
  Future<void> _sendInitializedNotification() async {
    appLog('[McpClient] Sending initialized notification');
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });

    try {
      final (httpResp, _) = await _postRequest(requestBody);
      appLog('[McpClient] initialized notification status: ${httpResp.statusCode}');
    } catch (e) {
      // Notification failures are non-fatal.
      appLog('[McpClient] initialized notification failed (ignored): $e');
    }
  }

  /// Fetches the tool list from the MCP server.
  Future<List<McpTool>> listTools() async {
    // Initialize the session on first use.
    if (_sessionId == null) {
      await initialize();
    }

    appLog('[McpClient] listTools request → $baseUrl');
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    appLog('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    appLog('[McpClient] Response status: ${httpResp.statusCode}');
    appLog('[McpClient] Response headers: ${httpResp.headers}');
    appLog('[McpClient] Response body (raw): ${_truncate(body, 500)}');

    if (httpResp.statusCode != 200) {
      appLog(
        '[McpClient] listTools HTTP error: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to list tools: ${httpResp.statusCode}');
    }

    final json = _decodeJson(body, 'listTools');

    // Check for JSON-RPC errors.
    if (json.containsKey('error')) {
      final error = json['error'];
      appLog('[McpClient] listTools JSON-RPC error: $error');
      throw Exception('MCP JSON-RPC error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    if (result == null) {
      appLog('[McpClient] result is null, full response: $json');
      return [];
    }

    final tools = result['tools'] as List<dynamic>? ?? [];
    appLog('[McpClient] Found ${tools.length} tools');
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

    appLog('[McpClient] callTool: $name');
    appLog('[McpClient] arguments: $arguments');

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': arguments},
    });
    appLog('[McpClient] Request: $requestBody');

    final (httpResp, body) = await _postRequest(requestBody);

    appLog('[McpClient] Response status: ${httpResp.statusCode}');
    appLog(
      '[McpClient] Response body (first 500 chars): ${_truncate(body, 500)}',
    );

    if (httpResp.statusCode != 200) {
      appLog(
        '[McpClient] callTool HTTP error: status=${httpResp.statusCode}, body=$body',
      );
      throw Exception('Failed to call tool: ${httpResp.statusCode}');
    }

    final json = _decodeJson(body, 'callTool');

    // Check for errors in the response.
    if (json.containsKey('error')) {
      final error = json['error'] as Map<String, dynamic>;
      appLog('[McpClient] Error: ${error['message']}');
      throw Exception('MCP error: ${error['message']}');
    }

    final result = json['result'] as Map<String, dynamic>?;
    if (result == null) {
      appLog('[McpClient] result is null, full response: $json');
      return '';
    }

    // Extract text results from the content array.
    final content = result['content'] as List<dynamic>? ?? [];
    final textContent = content
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n');

    appLog('[McpClient] Result length: ${textContent.length} chars');
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
      appLog('[McpClient] HTTP connection error: ${e.runtimeType}: $e');
      appLog('[McpClient] stackTrace: $stackTrace');
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
      appLog('[McpClient] $context JSON decode error: ${e.runtimeType}: $e');
      appLog('[McpClient] Response body: $body');
      appLog('[McpClient] stackTrace: $stackTrace');
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
    appLog('[McpClient] Detected SSE response, extracting data lines');
    final dataLines = <String>[];
    for (final line in trimmed.split('\n')) {
      if (line.startsWith('data: ')) {
        dataLines.add(line.substring(6)); // Content after `data: `
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5)); // Content after `data:` with no space
      }
    }

    if (dataLines.isEmpty) {
      appLog('[McpClient] No data lines found in SSE response: $trimmed');
      throw FormatException('No data lines found in SSE response');
    }

    final jsonStr = dataLines.join('');
    appLog('[McpClient] JSON extracted from SSE: ${_truncate(jsonStr, 200)}');
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
