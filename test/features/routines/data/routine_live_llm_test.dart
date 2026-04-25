import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/google_chat_delivery_service.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

const _routinePrompt =
    'LAN scan \u3092\u5b9f\u884c\u3057\u3001\u691c\u51fa\u3055\u308c\u305f\u7aef\u672b IP \u4e00\u89a7\u3092 workspace \u306e lan_devices.json \u306b\u4fdd\u5b58\u3057\u3066\u304f\u3060\u3055\u3044\u3002\n'
    '\u65e2\u5b58\u30d5\u30a1\u30a4\u30eb\u304c\u3042\u308c\u3070\u8aad\u307f\u8fbc\u307f\u3001\u524d\u56de\u3068\u306e\u5dee\u5206\u3092\u6bd4\u8f03\u3057\u3066\u304f\u3060\u3055\u3044\u3002\n'
    '\u65b0\u898f IP \u304c\u3042\u308c\u3070 Google Chat \u306b\u65b0\u898f\u7aef\u672b\u4e00\u89a7\u3060\u3051\u3092\u6295\u7a3f\u3057\u3066\u304f\u3060\u3055\u3044\u3002\n'
    '\u65b0\u898f IP \u304c\u306a\u3051\u308c\u3070\u30d5\u30a1\u30a4\u30eb\u3060\u3051\u66f4\u65b0\u3057\u3001\u6295\u7a3f\u3057\u306a\u3044\u3067\u304f\u3060\u3055\u3044\u3002';

void main() {
  final liveEnabled = Platform.environment['CAVERNO_ROUTINE_LIVE_LLM'] == '1';

  test(
    'live LLM completes the LAN watcher routine with file update and chat alert',
    () async {
      final baseUrl = _requiredEnv('CAVERNO_LLM_BASE_URL');
      final apiKey = _requiredEnv('CAVERNO_LLM_API_KEY');
      final model = _requiredEnv('CAVERNO_LLM_MODEL');
      final maxTokens = int.tryParse(
        Platform.environment['CAVERNO_ROUTINE_LIVE_MAX_TOKENS'] ?? '',
      );
      final temperature = double.tryParse(
        Platform.environment['CAVERNO_ROUTINE_LIVE_TEMPERATURE'] ?? '',
      );

      final workspace = Directory.systemTemp.createTempSync(
        'caverno-routine-live-',
      );
      final stateFile = File('${workspace.path}/lan_devices.json');
      const previousIps = ['192.168.100.1', '192.168.100.8'];
      const currentIps = ['192.168.100.1', '192.168.100.8', '192.168.100.42'];
      const newIp = '192.168.100.42';
      await stateFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(previousIps),
      );

      final toolService = _LiveRoutineMcpToolService(
        workspaceDirectory: workspace.path,
        lanIps: currentIps,
      );
      final deliveryService = _LiveRoutineGoogleChatDeliveryService();
      final settings = AppSettings.defaults().copyWith(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature ?? 0.2,
        maxTokens: maxTokens ?? 4096,
        googleChatWebhookUrl:
            'https://chat.googleapis.com/v1/spaces/live-test/messages?key=test&token=test',
      );
      final service = RoutineExecutionService(
        dataSource: ChatRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey),
        mcpToolService: toolService,
        googleChatDeliveryService: deliveryService,
        settings: settings,
      );
      final now = DateTime(2026, 4, 25, 15, 0);
      final routine = Routine(
        id: 'routine-live-lan-watch',
        name: 'LAN watcher live validation',
        prompt: _routinePrompt,
        createdAt: now,
        updatedAt: now,
        enabled: true,
        toolsEnabled: true,
        workspaceDirectory: workspace.path,
        allowWorkspaceWrites: true,
        completionAction: RoutineCompletionAction.promptGoogleChat,
      );

      try {
        final record = await service.execute(routine);

        expect(
          record.isSuccessful,
          isTrue,
          reason: _diagnostic(record, toolService, deliveryService, stateFile),
        );
        expect(
          toolService.executedToolNames,
          containsAll(['read_file', 'lan_scan', 'write_file']),
        );
        expect(
          record.toolNames,
          contains(RoutineExecutionService.googleChatPostToolName),
        );
        expect(deliveryService.messages, hasLength(1));
        expect(deliveryService.messages.single, contains(newIp));
        for (final previousIp in previousIps) {
          expect(deliveryService.messages.single, isNot(contains(previousIp)));
        }

        final savedContent = await stateFile.readAsString();
        for (final currentIp in currentIps) {
          expect(savedContent, contains(currentIp));
        }
      } finally {
        workspace.deleteSync(recursive: true);
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_ROUTINE_LIVE_LLM=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for routine live LLM validation.');
  }
  return value;
}

String _diagnostic(
  RoutineRunRecord record,
  _LiveRoutineMcpToolService toolService,
  _LiveRoutineGoogleChatDeliveryService deliveryService,
  File stateFile,
) {
  final buffer = StringBuffer()
    ..writeln('status=${record.status.name}')
    ..writeln('error=${record.error}')
    ..writeln('preview=${record.preview}')
    ..writeln('output=${record.output}')
    ..writeln('toolNames=${record.toolNames.join(',')}')
    ..writeln('executedToolNames=${toolService.executedToolNames.join(',')}')
    ..writeln('chatMessages=${deliveryService.messages.join(' | ')}');
  if (stateFile.existsSync()) {
    buffer.writeln('stateFile=${stateFile.readAsStringSync()}');
  }
  return buffer.toString();
}

Map<String, dynamic> _toolDefinition({
  required String name,
  required String description,
  Map<String, dynamic> parameters = const {'type': 'object', 'properties': {}},
}) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

class _LiveRoutineMcpToolService extends McpToolService {
  _LiveRoutineMcpToolService({
    required this.workspaceDirectory,
    required this.lanIps,
  });

  final String workspaceDirectory;
  final List<String> lanIps;
  final List<String> executedToolNames = [];

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return [
      _toolDefinition(
        name: 'read_file',
        description:
            'Read a UTF-8 text file from the configured routine workspace.',
        parameters: const {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      ),
      _toolDefinition(
        name: 'lan_scan',
        description:
            'Scan the local LAN and return active hosts with IP addresses.',
        parameters: const {
          'type': 'object',
          'properties': {
            'ip_version': {
              'type': 'string',
              'enum': ['auto', 'ipv4', 'ipv6'],
            },
          },
        },
      ),
      _toolDefinition(
        name: 'write_file',
        description:
            'Write a full UTF-8 text file inside the configured routine workspace.',
        parameters: const {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'content': {'type': 'string'},
            'contents': {
              'description': 'Alternative content field accepted by the app.',
            },
          },
          'required': ['path'],
        },
      ),
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return switch (name) {
      'read_file' => _readFile(arguments),
      'lan_scan' => _lanScan(),
      'write_file' => _writeFile(arguments),
      _ => McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported live validation tool'}),
        isSuccess: false,
        errorMessage: 'Unsupported live validation tool',
      ),
    };
  }

  McpToolResult _readFile(Map<String, dynamic> arguments) {
    final path = (arguments['path'] as String?)?.trim() ?? '';
    final file = path.isEmpty
        ? File('$workspaceDirectory/lan_devices.json')
        : File(path);
    if (!file.existsSync()) {
      return McpToolResult(
        toolName: 'read_file',
        result: jsonEncode({'error': 'File does not exist: ${file.path}'}),
        isSuccess: false,
        errorMessage: 'File does not exist',
      );
    }
    return McpToolResult(
      toolName: 'read_file',
      result: jsonEncode({
        'path': file.path,
        'content': file.readAsStringSync(),
      }),
      isSuccess: true,
    );
  }

  McpToolResult _lanScan() {
    return McpToolResult(
      toolName: 'lan_scan',
      result: jsonEncode({
        'subnet': '192.168.100.0/24',
        'hosts_scanned': 256,
        'hosts_found': lanIps.length,
        'hosts': [
          for (final ip in lanIps)
            {'ip': ip, 'ip_version': 'ipv4', 'response_time_ms': 3.2},
        ],
      }),
      isSuccess: true,
    );
  }

  McpToolResult _writeFile(Map<String, dynamic> arguments) {
    final path = (arguments['path'] as String?)?.trim() ?? '';
    final content = arguments['content'] ?? arguments['contents'];
    if (path.isEmpty || content == null) {
      return McpToolResult(
        toolName: 'write_file',
        result: jsonEncode({'error': 'path and content are required'}),
        isSuccess: false,
        errorMessage: 'path and content are required',
      );
    }
    final file = File(path);
    file.parent.createSync(recursive: true);
    final text = content is String
        ? content
        : const JsonEncoder.withIndent('  ').convert(content);
    file.writeAsStringSync(text);
    return McpToolResult(
      toolName: 'write_file',
      result: jsonEncode({'path': file.path, 'bytes_written': text.length}),
      isSuccess: true,
    );
  }
}

class _LiveRoutineGoogleChatDeliveryService extends GoogleChatDeliveryService {
  final List<String> messages = [];

  @override
  Future<GoogleChatDeliveryResult> sendMessage({
    required String webhookUrl,
    required String text,
  }) async {
    messages.add(text);
    return GoogleChatDeliveryResult(
      isSuccessful: true,
      message: 'Captured Google Chat message.',
      deliveredAt: DateTime(2026, 4, 25, 15, 0, messages.length),
    );
  }
}
