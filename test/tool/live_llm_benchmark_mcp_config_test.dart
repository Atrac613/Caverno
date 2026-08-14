import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_benchmark_mcp_config.dart';

void main() {
  group('live benchmark MCP config', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'caverno-benchmark-mcp-config-',
      );
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('keeps built-in-only behavior without an explicit path', () {
      expect(loadLiveLlmBenchmarkMcpServers(null), isEmpty);
      expect(loadLiveLlmBenchmarkMcpServers('  '), isEmpty);
    });

    test('loads trusted HTTP and stdio servers from a list', () {
      final file = _writeConfig(temporaryDirectory, [
        {
          'type': 'http',
          'url': 'http://mcp.example.test/mcp',
          'enabled': true,
          'trustState': 'trusted',
        },
        {
          'type': 'stdio',
          'command': '/usr/bin/example-mcp',
          'args': ['serve'],
          'env': {'EXAMPLE_TOKEN': 'secret-value'},
          'enabled': true,
          'trustState': 'trusted',
        },
      ]);

      final servers = loadLiveLlmBenchmarkMcpServers(file.path);

      expect(servers, hasLength(2));
      expect(servers.first.type, McpServerType.http);
      expect(servers.last.type, McpServerType.stdio);
      expect(servers.last.normalizedEnv['EXAMPLE_TOKEN'], 'secret-value');
    });

    test('loads list and keyed object mcpServers forms', () {
      final listFile = _writeConfig(temporaryDirectory, {
        'mcpServers': [_trustedHttpServer()],
      });
      final keyedFile = _writeConfig(temporaryDirectory, {
        'mcpServers': {'network': _trustedHttpServer()},
      });

      expect(loadLiveLlmBenchmarkMcpServers(listFile.path), hasLength(1));
      expect(loadLiveLlmBenchmarkMcpServers(keyedFile.path), hasLength(1));
    });

    test('rejects malformed or empty payloads', () {
      final malformed = File('${temporaryDirectory.path}/malformed.json')
        ..writeAsStringSync('{');
      final empty = _writeConfig(temporaryDirectory, const <Object?>[]);

      expect(
        () => loadLiveLlmBenchmarkMcpServers(malformed.path),
        throwsFormatException,
      );
      expect(
        () => loadLiveLlmBenchmarkMcpServers(empty.path),
        throwsFormatException,
      );
    });

    test('rejects disabled, invalid, or untrusted servers', () {
      for (final record in [
        {..._trustedHttpServer(), 'enabled': false},
        {..._trustedHttpServer(), 'url': ''},
        {..._trustedHttpServer(), 'trustState': 'pending'},
      ]) {
        final file = _writeConfig(temporaryDirectory, [record]);
        expect(
          () => loadLiveLlmBenchmarkMcpServers(file.path),
          throwsFormatException,
        );
      }
    });

    test('rejects HTTP identifiers that could expose credentials', () {
      for (final url in [
        'http://user:password@mcp.example.test/mcp',
        'http://mcp.example.test/mcp?token=secret',
        'http://mcp.example.test/mcp#secret',
      ]) {
        final file = _writeConfig(temporaryDirectory, [
          {..._trustedHttpServer(), 'url': url},
        ]);
        expect(
          () => loadLiveLlmBenchmarkMcpServers(file.path),
          throwsFormatException,
        );
      }
    });
  });
}

File _writeConfig(Directory directory, Object value) {
  final file = File(
    '${directory.path}/config-${directory.listSync().length}.json',
  );
  file.writeAsStringSync(jsonEncode(value));
  return file;
}

Map<String, Object> _trustedHttpServer() => {
  'type': 'http',
  'url': 'https://mcp.example.test/mcp',
  'enabled': true,
  'trustState': 'trusted',
};
