import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

List<McpServerConfig> loadLiveLlmBenchmarkMcpServers(String? configPath) {
  final normalizedPath = configPath?.trim() ?? '';
  if (normalizedPath.isEmpty) {
    return const <McpServerConfig>[];
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(File(normalizedPath).readAsStringSync());
  } on FormatException catch (error) {
    throw FormatException(
      'Invalid benchmark MCP config JSON: ${error.message}',
    );
  } on FileSystemException catch (error) {
    throw FormatException(
      'Unable to read the benchmark MCP config: ${error.message}',
    );
  }

  final records = _serverRecords(decoded);
  if (records.isEmpty) {
    throw const FormatException(
      'The benchmark MCP config must contain at least one server.',
    );
  }

  return List<McpServerConfig>.unmodifiable([
    for (var index = 0; index < records.length; index += 1)
      _validatedServer(records[index], index),
  ]);
}

List<Object?> _serverRecords(Object? decoded) {
  final Object? payload = switch (decoded) {
    List<Object?>() => decoded,
    Map<Object?, Object?>() => decoded['mcpServers'],
    _ => null,
  };
  return switch (payload) {
    List<Object?>() => payload,
    Map<Object?, Object?>() => payload.values.toList(growable: false),
    _ => throw const FormatException(
      'The benchmark MCP config must be a server list or contain mcpServers.',
    ),
  };
}

McpServerConfig _validatedServer(Object? record, int index) {
  if (record is! Map) {
    throw FormatException('MCP server at index $index must be a JSON object.');
  }

  late final McpServerConfig server;
  try {
    server = McpServerConfig.fromJson(Map<String, dynamic>.from(record));
  } catch (_) {
    throw FormatException('MCP server at index $index is invalid.');
  }

  if (!server.exposesToolsToModel) {
    throw FormatException(
      'MCP server at index $index must be enabled, valid, and trusted.',
    );
  }
  if (server.type == McpServerType.http) {
    _validateSafeHttpUrl(server.normalizedUrl, index);
  }
  return server;
}

void _validateSafeHttpUrl(String value, int index) {
  final uri = Uri.tryParse(value);
  final validOrigin =
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
  if (!validOrigin) {
    throw FormatException(
      'HTTP MCP server at index $index must use an absolute HTTP(S) URL.',
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw FormatException(
      'HTTP MCP server at index $index must not include credentials, a query, or a fragment.',
    );
  }
}
