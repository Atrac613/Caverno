import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/utils/logger.dart';

/// Common interface for MCP clients regardless of transport.
abstract class McpClientBase {
  /// Human-readable identifier (URL for HTTP, command for stdio).
  String get identifier;

  /// Initialize the MCP session (protocol handshake).
  Future<void> initialize();

  /// Fetch available tools from the server.
  Future<List<McpTool>> listTools();

  /// Execute a tool by name with the given arguments.
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  });

  /// Release resources (close HTTP client, kill process, etc.).
  Future<void> dispose();
}

class McpClient implements McpClientBase {
  McpClient({required this.baseUrl});

  final String baseUrl;

  @override
  String get identifier => baseUrl;

  /// MCP session ID for the streamable HTTP transport.
  String? _sessionId;
  bool _isInitialized = false;

  /// Returns the current session ID.
  String? get sessionId => _sessionId;

  @override
  Future<void> dispose() async {
    // HTTP client has no persistent resources to clean up.
  }

  /// Initializes the MCP server and stores the session ID.
  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    appLog('[McpClient] initialize request → $baseUrl');
    const requestId = 1;
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
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
    final json = _decodeJson(body, 'initialize', expectedId: requestId);

    if (json.containsKey('error')) {
      final error = json['error'];
      appLog('[McpClient] initialize JSON-RPC error: $error');
      throw Exception('MCP initialize error: $error');
    }

    final result = json['result'] as Map<String, dynamic>?;
    appLog('[McpClient] Server info: $result');
    _isInitialized = true;

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
      appLog(
        '[McpClient] initialized notification status: ${httpResp.statusCode}',
      );
    } catch (e) {
      // Notification failures are non-fatal.
      appLog('[McpClient] initialized notification failed (ignored): $e');
    }
  }

  /// Fetches the tool list from the MCP server.
  @override
  Future<List<McpTool>> listTools() async {
    // Initialize the session on first use.
    if (!_isInitialized) {
      await initialize();
    }

    appLog('[McpClient] listTools request → $baseUrl');
    const requestId = 2;
    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
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

    final json = _decodeJson(body, 'listTools', expectedId: requestId);

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
  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    // Initialize the session on first use.
    if (!_isInitialized) {
      await initialize();
    }

    appLog('[McpClient] callTool: $name');
    appLog('[McpClient] arguments: $arguments');
    const requestId = 3;

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
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

    final json = _decodeJson(body, 'callTool', expectedId: requestId);

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

  /// Helper for JSON decoding, including SSE-style responses and concatenated
  /// JSON documents emitted by some MCP HTTP transports.
  Map<String, dynamic> _decodeJson(
    String body,
    String context, {
    int? expectedId,
  }) {
    try {
      final jsonBodies = _extractJsonDocuments(body);
      final jsonObjects = <Map<String, dynamic>>[];

      for (final jsonBody in jsonBodies) {
        final decoded = jsonDecode(jsonBody);
        jsonObjects.addAll(_extractJsonResponseCandidates(decoded));
      }

      if (jsonObjects.isEmpty) {
        throw const FormatException('No JSON object found in response');
      }

      if (jsonObjects.length > 1) {
        appLog(
          '[McpClient] $context extracted ${jsonObjects.length} JSON documents, selecting the best JSON-RPC match',
        );
      }

      return _selectJsonResponse(jsonObjects, expectedId: expectedId);
    } catch (e, stackTrace) {
      appLog('[McpClient] $context JSON decode error: ${e.runtimeType}: $e');
      appLog('[McpClient] Response body: $body');
      appLog('[McpClient] stackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Extracts JSON documents from a plain or SSE-style response body.
  ///
  /// Some MCP servers concatenate transport metadata and the JSON-RPC payload
  /// without a delimiter, so this returns every JSON document found.
  List<String> _extractJsonDocuments(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    // Return plain JSON responses unchanged.
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return _splitJsonDocuments(trimmed);
    }

    // Extract and join `data:` lines from SSE responses.
    appLog('[McpClient] Detected SSE response, extracting data lines');
    final eventPayloads = <String>[];
    final currentEventDataLines = <String>[];

    void flushEvent() {
      if (currentEventDataLines.isEmpty) {
        return;
      }
      eventPayloads.add(currentEventDataLines.join('\n'));
      currentEventDataLines.clear();
    }

    for (final line in trimmed.split('\n')) {
      if (line.trim().isEmpty) {
        flushEvent();
        continue;
      }
      if (line.startsWith('data: ')) {
        currentEventDataLines.add(line.substring(6));
      } else if (line.startsWith('data:')) {
        currentEventDataLines.add(line.substring(5));
      }
    }
    flushEvent();

    if (eventPayloads.isEmpty) {
      appLog('[McpClient] No data lines found in SSE response: $trimmed');
      throw const FormatException('No data lines found in SSE response');
    }

    final jsonBodies = <String>[];
    for (final payload in eventPayloads) {
      final normalizedPayload = payload.trim();
      if (normalizedPayload.isEmpty) {
        continue;
      }
      if (!normalizedPayload.startsWith('{') &&
          !normalizedPayload.startsWith('[')) {
        continue;
      }
      jsonBodies.addAll(_splitJsonDocuments(normalizedPayload));
    }

    if (jsonBodies.isEmpty) {
      throw const FormatException('No JSON payload found in SSE response');
    }

    appLog(
      '[McpClient] Extracted ${jsonBodies.length} JSON document(s) from response',
    );
    return jsonBodies;
  }

  Map<String, dynamic> _selectJsonResponse(
    List<Map<String, dynamic>> jsonObjects, {
    int? expectedId,
  }) {
    if (expectedId != null) {
      for (final json in jsonObjects.reversed) {
        if (json['jsonrpc'] == '2.0' && json['id'] == expectedId) {
          return json;
        }
      }
    }

    for (final json in jsonObjects.reversed) {
      if (json['jsonrpc'] == '2.0' &&
          (json.containsKey('result') || json.containsKey('error'))) {
        return json;
      }
    }

    for (final json in jsonObjects.reversed) {
      if (json['jsonrpc'] == '2.0') {
        return json;
      }
    }

    return jsonObjects.last;
  }

  List<Map<String, dynamic>> _extractJsonResponseCandidates(dynamic value) {
    final map = _coerceJsonMap(value);
    if (map == null) {
      return const [];
    }

    final candidates = <Map<String, dynamic>>[map];
    final nestedResponse = _coerceJsonMap(map['response']);
    if (nestedResponse != null) {
      candidates.addAll(_extractJsonResponseCandidates(nestedResponse));
    }
    return candidates;
  }

  Map<String, dynamic>? _coerceJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<String> _splitJsonDocuments(String source) {
    final documents = <String>[];
    var index = 0;

    while (index < source.length) {
      index = _skipWhitespace(source, index);
      if (index >= source.length) {
        break;
      }

      final current = source[index];
      if (current != '{' && current != '[') {
        throw FormatException(
          'Unexpected character while reading JSON response: $current',
        );
      }

      final end = _findJsonDocumentEnd(source, index);
      if (end == null) {
        throw const FormatException('Unterminated JSON document in response');
      }

      documents.add(source.substring(index, end + 1));
      index = end + 1;
    }

    return documents;
  }

  int _skipWhitespace(String source, int index) {
    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit == 0x20 ||
          codeUnit == 0x0A ||
          codeUnit == 0x0D ||
          codeUnit == 0x09) {
        index += 1;
        continue;
      }
      break;
    }
    return index;
  }

  int? _findJsonDocumentEnd(String source, int startIndex) {
    final stack = <String>[];
    var index = startIndex;

    while (index < source.length) {
      final char = source[index];
      if (char == '"') {
        final stringEnd = _findJsonStringEnd(source, index);
        if (stringEnd == null) {
          return null;
        }
        index = stringEnd + 1;
        continue;
      }

      if (char == '{' || char == '[') {
        stack.add(char);
      } else if (char == '}') {
        if (stack.isEmpty || stack.last != '{') {
          return null;
        }
        stack.removeLast();
        if (stack.isEmpty) {
          return index;
        }
      } else if (char == ']') {
        if (stack.isEmpty || stack.last != '[') {
          return null;
        }
        stack.removeLast();
        if (stack.isEmpty) {
          return index;
        }
      }

      index += 1;
    }

    return null;
  }

  int? _findJsonStringEnd(String source, int startIndex) {
    var index = startIndex + 1;
    while (index < source.length) {
      final char = source[index];
      if (char == r'\') {
        index += 2;
        continue;
      }
      if (char == '"') {
        return index;
      }
      index += 1;
    }
    return null;
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
