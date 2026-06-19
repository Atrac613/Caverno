import 'dart:convert';
import 'dart:io';

import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/lsp_diagnostic_feedback_provider.dart';

class LspJsonRpcMessageCodec {
  const LspJsonRpcMessageCodec._();

  static List<int> encode(Map<String, dynamic> message) {
    final body = utf8.encode(jsonEncode(message));
    final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');
    return [...header, ...body];
  }

  static Map<String, dynamic> request({
    required Object id,
    required String method,
    Map<String, dynamic>? params,
  }) {
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
    };
    if (params != null) {
      message['params'] = params;
    }
    return message;
  }

  static Map<String, dynamic> notification({
    required String method,
    Map<String, dynamic>? params,
  }) {
    final message = <String, dynamic>{'jsonrpc': '2.0', 'method': method};
    if (params != null) {
      message['params'] = params;
    }
    return message;
  }
}

class LspJsonRpcMessageBuffer {
  final List<int> _buffer = [];

  List<Map<String, dynamic>> addBytes(List<int> bytes) {
    _buffer.addAll(bytes);
    final messages = <Map<String, dynamic>>[];
    while (true) {
      final headerEnd = _headerEndIndex(_buffer);
      if (headerEnd < 0) {
        break;
      }

      final header = ascii.decode(_buffer.sublist(0, headerEnd));
      final contentLength = _contentLength(header);
      if (contentLength == null) {
        throw const FormatException('Missing Content-Length header.');
      }

      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;
      if (_buffer.length < bodyEnd) {
        break;
      }

      final body = utf8.decode(_buffer.sublist(bodyStart, bodyEnd));
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('LSP JSON-RPC body must be an object.');
      }
      messages.add(Map<String, dynamic>.from(decoded));
      _buffer.removeRange(0, bodyEnd);
    }
    return messages;
  }

  int _headerEndIndex(List<int> bytes) {
    for (var index = 0; index <= bytes.length - 4; index += 1) {
      if (bytes[index] == 13 &&
          bytes[index + 1] == 10 &&
          bytes[index + 2] == 13 &&
          bytes[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  int? _contentLength(String header) {
    for (final line in header.split('\r\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      if (name != 'content-length') {
        continue;
      }
      return int.tryParse(line.substring(separator + 1).trim());
    }
    return null;
  }
}

class LspPublishedDiagnosticStore {
  final Map<String, List<LspDiagnostic>> _diagnosticsByUri = {};

  void applyMessage(Map<String, dynamic> message) {
    if (message['method'] != 'textDocument/publishDiagnostics') {
      return;
    }
    final params = message['params'];
    if (params is! Map) {
      return;
    }
    final uri = _stringValue(params['uri']);
    final diagnostics = params['diagnostics'];
    if (uri == null || diagnostics is! List) {
      return;
    }
    _diagnosticsByUri[uri] = diagnostics
        .whereType<Map>()
        .map((item) => _diagnosticFromPayload(uri, item))
        .whereType<LspDiagnostic>()
        .toList(growable: false);
  }

  List<LspDiagnostic> diagnosticsForUris(Iterable<String> uris) {
    final results = <LspDiagnostic>[];
    for (final uri in uris) {
      results.addAll(_diagnosticsByUri[uri] ?? const []);
    }
    return results;
  }

  bool hasPublicationForAll(Iterable<String> uris) {
    final requestedUris = uris.toList(growable: false);
    return requestedUris.isNotEmpty &&
        requestedUris.every(_diagnosticsByUri.containsKey);
  }

  LspDiagnostic? _diagnosticFromPayload(
    String uri,
    Map<dynamic, dynamic> item,
  ) {
    final range = item['range'];
    final start = range is Map ? range['start'] : null;
    if (start is! Map) {
      return null;
    }
    final line = _intValue(start['line']);
    final character = _intValue(start['character']);
    final message = _stringValue(item['message']);
    if (line == null || character == null || message == null) {
      return null;
    }
    return LspDiagnostic(
      uri: uri,
      startLine: line,
      startCharacter: character,
      severity: _intValue(item['severity']),
      code: item['code'],
      source: _stringValue(item['source']),
      message: message,
    );
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}

class LspJsonRpcDiagnosticBridge implements LspDiagnosticClient {
  LspJsonRpcDiagnosticBridge({
    required this.providerName,
    required this.languageId,
    this.supportsDocumentSymbols = false,
    this.supportsGoToDefinition = false,
    LspPublishedDiagnosticStore? diagnosticStore,
  }) : _diagnosticStore = diagnosticStore ?? LspPublishedDiagnosticStore();

  @override
  final String providerName;
  final String languageId;
  @override
  final bool supportsDocumentSymbols;
  @override
  final bool supportsGoToDefinition;
  final LspPublishedDiagnosticStore _diagnosticStore;
  final LspJsonRpcMessageBuffer _messageBuffer = LspJsonRpcMessageBuffer();

  List<Map<String, dynamic>> handleIncomingBytes(List<int> bytes) {
    final messages = _messageBuffer.addBytes(bytes);
    for (final message in messages) {
      handleIncomingMessage(message);
    }
    return messages;
  }

  void handleIncomingMessage(Map<String, dynamic> message) {
    _diagnosticStore.applyMessage(message);
  }

  bool hasPublishedDiagnosticsForUris(Iterable<String> uris) {
    return _diagnosticStore.hasPublicationForAll(uris);
  }

  Map<String, dynamic> initializeRequest({
    required Object id,
    required String rootUri,
    int? processId,
  }) {
    final textDocumentCapabilities = <String, dynamic>{
      'publishDiagnostics': {},
      'synchronization': {'didSave': true},
      if (supportsDocumentSymbols) 'documentSymbol': {},
      if (supportsGoToDefinition) 'definition': {},
    };
    return LspJsonRpcMessageCodec.request(
      id: id,
      method: 'initialize',
      params: {
        'processId': processId,
        'rootUri': rootUri,
        'capabilities': {
          'textDocument': textDocumentCapabilities,
          'workspace': {},
        },
      },
    );
  }

  Map<String, dynamic> didOpenNotification({
    required String uri,
    required String text,
    int version = 1,
  }) {
    return LspJsonRpcMessageCodec.notification(
      method: 'textDocument/didOpen',
      params: {
        'textDocument': {
          'uri': uri,
          'languageId': languageId,
          'version': version,
          'text': text,
        },
      },
    );
  }

  Map<String, dynamic> initializedNotification() {
    return LspJsonRpcMessageCodec.notification(
      method: 'initialized',
      params: const {},
    );
  }

  Map<String, dynamic> didChangeNotification({
    required String uri,
    required String text,
    required int version,
  }) {
    return LspJsonRpcMessageCodec.notification(
      method: 'textDocument/didChange',
      params: {
        'textDocument': {'uri': uri, 'version': version},
        'contentChanges': [
          {'text': text},
        ],
      },
    );
  }

  Map<String, dynamic> documentSymbolRequest({
    required Object id,
    required String uri,
  }) {
    return LspJsonRpcMessageCodec.request(
      id: id,
      method: 'textDocument/documentSymbol',
      params: {
        'textDocument': {'uri': uri},
      },
    );
  }

  Map<String, dynamic> definitionRequest({
    required Object id,
    required String uri,
    required int line,
    required int character,
  }) {
    return LspJsonRpcMessageCodec.request(
      id: id,
      method: 'textDocument/definition',
      params: {
        'textDocument': {'uri': uri},
        'position': {'line': line, 'character': character},
      },
    );
  }

  List<LspDocumentSymbol> documentSymbolsFromResponse({
    required String uri,
    required Map<String, dynamic> response,
  }) {
    return documentSymbolsFromResult(uri: uri, result: response['result']);
  }

  List<LspDocumentSymbol> documentSymbolsFromResult({
    required String uri,
    required Object? result,
  }) {
    if (result is! List) {
      return const [];
    }
    return result
        .whereType<Map>()
        .map((item) => _documentSymbolFromPayload(fallbackUri: uri, item: item))
        .whereType<LspDocumentSymbol>()
        .toList(growable: false);
  }

  List<LspDefinitionLocation> definitionLocationsFromResponse({
    required Map<String, dynamic> response,
  }) {
    return definitionLocationsFromResult(result: response['result']);
  }

  List<LspDefinitionLocation> definitionLocationsFromResult({
    required Object? result,
  }) {
    if (result == null) {
      return const [];
    }
    if (result is Map) {
      final location = _definitionLocationFromPayload(result);
      return location == null ? const [] : [location];
    }
    if (result is! List) {
      return const [];
    }
    return result
        .whereType<Map>()
        .map(_definitionLocationFromPayload)
        .whereType<LspDefinitionLocation>()
        .toList(growable: false);
  }

  @override
  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final uris = _changedFileUris(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    return _diagnosticStore.diagnosticsForUris(uris);
  }

  List<String> _changedFileUris({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final root = Directory(projectRoot).absolute.path;
    final uris = <String>[];
    final seen = <String>{};
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: root,
      );
      if (absolutePath == null ||
          !DartProjectPath.isInsideRoot(absolutePath, root)) {
        continue;
      }
      final key = DartProjectPath.pathKey(absolutePath);
      if (!seen.add(key)) {
        continue;
      }
      uris.add(File(absolutePath).absolute.uri.toString());
    }
    return uris;
  }

  LspDocumentSymbol? _documentSymbolFromPayload({
    required String fallbackUri,
    required Map<dynamic, dynamic> item,
    String? containerName,
  }) {
    final location = item['location'];
    if (location is Map) {
      return _symbolInformationFromPayload(
        fallbackUri: fallbackUri,
        item: item,
        location: location,
      );
    }

    final name = _stringValue(item['name']);
    final kind = _intValue(item['kind']);
    final range = item['range'];
    final start = range is Map ? range['start'] : null;
    if (name == null || kind == null || start is! Map) {
      return null;
    }
    final startLine = _intValue(start['line']);
    final startCharacter = _intValue(start['character']);
    if (startLine == null || startCharacter == null) {
      return null;
    }
    final children = item['children'] is List
        ? (item['children'] as List)
              .whereType<Map>()
              .map(
                (child) => _documentSymbolFromPayload(
                  fallbackUri: fallbackUri,
                  item: child,
                  containerName: name,
                ),
              )
              .whereType<LspDocumentSymbol>()
              .toList(growable: false)
        : const <LspDocumentSymbol>[];
    return LspDocumentSymbol(
      uri: fallbackUri,
      name: name,
      kind: kind,
      kindLabel: _symbolKindLabel(kind),
      startLine: startLine,
      startCharacter: startCharacter,
      detail: _stringValue(item['detail']),
      containerName: containerName,
      children: children,
    );
  }

  LspDefinitionLocation? _definitionLocationFromPayload(
    Map<dynamic, dynamic> item,
  ) {
    final targetUri = _stringValue(item['targetUri']);
    if (targetUri != null) {
      final selectionRange = item['targetSelectionRange'];
      final targetRange = item['targetRange'];
      final range = selectionRange is Map
          ? selectionRange
          : targetRange is Map
          ? targetRange
          : null;
      if (range == null) {
        return null;
      }
      return _definitionLocationFromRange(uri: targetUri, range: range);
    }

    final uri = _stringValue(item['uri']);
    final range = item['range'];
    if (uri == null || range is! Map) {
      return null;
    }
    return _definitionLocationFromRange(uri: uri, range: range);
  }

  LspDefinitionLocation? _definitionLocationFromRange({
    required String uri,
    required Map<dynamic, dynamic> range,
  }) {
    final start = range['start'];
    if (start is! Map) {
      return null;
    }
    final startLine = _intValue(start['line']);
    final startCharacter = _intValue(start['character']);
    if (startLine == null || startCharacter == null) {
      return null;
    }
    final end = range['end'];
    return LspDefinitionLocation(
      uri: uri,
      startLine: startLine,
      startCharacter: startCharacter,
      endLine: end is Map ? _intValue(end['line']) : null,
      endCharacter: end is Map ? _intValue(end['character']) : null,
    );
  }

  LspDocumentSymbol? _symbolInformationFromPayload({
    required String fallbackUri,
    required Map<dynamic, dynamic> item,
    required Map<dynamic, dynamic> location,
  }) {
    final name = _stringValue(item['name']);
    final kind = _intValue(item['kind']);
    final uri = _stringValue(location['uri']) ?? fallbackUri;
    final range = location['range'];
    final start = range is Map ? range['start'] : null;
    if (name == null || kind == null || start is! Map) {
      return null;
    }
    final startLine = _intValue(start['line']);
    final startCharacter = _intValue(start['character']);
    if (startLine == null || startCharacter == null) {
      return null;
    }
    return LspDocumentSymbol(
      uri: uri,
      name: name,
      kind: kind,
      kindLabel: _symbolKindLabel(kind),
      startLine: startLine,
      startCharacter: startCharacter,
      containerName: _stringValue(item['containerName']),
    );
  }

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  String? _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String _symbolKindLabel(int kind) {
    return switch (kind) {
      1 => 'File',
      2 => 'Module',
      3 => 'Namespace',
      4 => 'Package',
      5 => 'Class',
      6 => 'Method',
      7 => 'Property',
      8 => 'Field',
      9 => 'Constructor',
      10 => 'Enum',
      11 => 'Interface',
      12 => 'Function',
      13 => 'Variable',
      14 => 'Constant',
      15 => 'String',
      16 => 'Number',
      17 => 'Boolean',
      18 => 'Array',
      19 => 'Object',
      20 => 'Key',
      21 => 'Null',
      22 => 'EnumMember',
      23 => 'Struct',
      24 => 'Event',
      25 => 'Operator',
      26 => 'TypeParameter',
      _ => 'Symbol',
    };
  }
}
