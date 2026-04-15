import 'dart:io';

import 'package:caverno/features/chat/data/datasources/mcp_client.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpToolEntity.toOpenAiTool', () {
    test('sanitizes MCP server details in the tool description', () {
      const tool = McpToolEntity(
        name: 'remote_search',
        description: 'Search remote content',
        inputSchema: {'type': 'object'},
        sourceUrl: 'https://user:secret@example.com:8080/mcp?token=abc',
      );

      final openAiTool = tool.toOpenAiTool();
      final function = openAiTool['function']! as Map<String, dynamic>;
      final description = function['description']! as String;

      expect(description, contains('example.com:8080'));
      expect(description, isNot(contains('secret')));
      expect(description, isNot(contains('token')));
      expect(description, isNot(contains('/mcp')));
    });
  });

  group('McpToolService', () {
    test(
      'namespaces remote tools that collide with built-in tools and routes calls',
      () async {
        final client = _FakeMcpClient(
          baseUrl: 'https://user:secret@example.com:8080/mcp?token=abc',
          tools: [
            McpTool(
              name: 'ping',
              description: 'Remote ping tool',
              inputSchema: {'type': 'object'},
            ),
          ],
          results: {'ping': 'remote pong'},
        );
        final service = McpToolService(mcpClients: [client]);

        await service.connect();

        expect(service.status, McpConnectionStatus.connected);
        expect(service.tools, hasLength(1));

        final remoteTool = service.tools.single;
        expect(remoteTool.originalName, 'ping');
        expect(remoteTool.name, isNot('ping'));
        expect(remoteTool.name, startsWith('ping__'));

        final toolDefinitions = service.getOpenAiToolDefinitions();
        final functionNames = toolDefinitions
            .map(
              (tool) =>
                  (tool['function']! as Map<String, dynamic>)['name']!
                      as String,
            )
            .toList();

        expect(functionNames.where((name) => name == 'ping'), hasLength(1));
        expect(functionNames, contains(remoteTool.name));

        final result = await service.executeTool(
          name: remoteTool.name,
          arguments: const {},
        );

        expect(result.isSuccess, isTrue);
        expect(result.result, 'remote pong');
        expect(client.calledToolNames, ['ping']);
      },
    );

    group('rollback_last_file_change', () {
      late Directory tempDir;
      late McpToolService service;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'mcp_tool_service_test_',
        );
        service = McpToolService();
      });

      tearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('restores the previous file contents', () async {
        final path =
            '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}sample.txt';
        final file = File(path);
        file.createSync(recursive: true);
        file.writeAsStringSync('before\n');

        final writeResult = await service.executeTool(
          name: 'write_file',
          arguments: {'path': path, 'content': 'after\n'},
        );
        expect(writeResult.isSuccess, isTrue);

        final preview = await service.previewLastFileRollbackChange();
        expect(preview, isNotNull);
        expect(preview!.path, path);
        expect(preview.preview, contains('-after'));
        expect(preview.preview, contains('+before'));

        final rollbackResult = await service.executeTool(
          name: 'rollback_last_file_change',
          arguments: const {},
        );
        expect(rollbackResult.isSuccess, isTrue);
        expect(await file.readAsString(), 'before\n');
      });

      test('removes a newly created file', () async {
        final path =
            '${tempDir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}created.txt';

        final writeResult = await service.executeTool(
          name: 'write_file',
          arguments: {'path': path, 'content': 'created\n'},
        );
        expect(writeResult.isSuccess, isTrue);
        expect(File(path).existsSync(), isTrue);

        final rollbackResult = await service.executeTool(
          name: 'rollback_last_file_change',
          arguments: const {},
        );
        expect(rollbackResult.isSuccess, isTrue);
        expect(File(path).existsSync(), isFalse);
      });
    });
  });
}

class _FakeMcpClient extends McpClient {
  _FakeMcpClient({
    required super.baseUrl,
    required this.tools,
    Map<String, String>? results,
  }) : results = results ?? const {};

  final List<McpTool> tools;
  final Map<String, String> results;
  final List<String> calledToolNames = [];

  @override
  Future<List<McpTool>> listTools() async => tools;

  @override
  Future<String> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    calledToolNames.add(name);
    return results[name] ?? '';
  }
}
