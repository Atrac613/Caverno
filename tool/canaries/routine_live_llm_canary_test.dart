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
    'Run a LAN scan and save the detected device IP list to '
    'lan_devices.json in the routine workspace. If the existing file is '
    'present, read it first and compare the previous IP list with the current '
    'scan. If there are newly discovered IPs, post only the newly discovered '
    'IP list to Google Chat. If there are no newly discovered IPs, update only '
    'lan_devices.json and do not post to Google Chat.';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_ROUTINE_LIVE_CANARY'] == '1';

  test(
    'live LLM completes the LAN watcher routine with file update and chat alert',
    () async {
      await _runLanWatcherScenario(
        previousIps: const ['192.168.100.1', '192.168.100.8'],
        currentIps: const ['192.168.100.1', '192.168.100.8', '192.168.100.42'],
        expectedPostedIps: const ['192.168.100.42'],
        expectGoogleChatPost: true,
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_ROUTINE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM updates the LAN watcher file without posting when no IP is new',
    () async {
      await _runLanWatcherScenario(
        previousIps: const ['192.168.100.1', '192.168.100.8'],
        currentIps: const ['192.168.100.1', '192.168.100.8'],
        expectedPostedIps: const <String>[],
        expectGoogleChatPost: false,
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_ROUTINE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM records a LAN scan failure without posting to Google Chat',
    () async {
      await _runLanWatcherScenario(
        previousIps: const ['192.168.100.1', '192.168.100.8'],
        currentIps: const <String>[],
        expectedPostedIps: const <String>[],
        expectGoogleChatPost: false,
        requireWriteFile: false,
        lanScanFailureMessage: 'LAN scan adapter is unavailable.',
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_ROUTINE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM can write LAN state with the contents argument alias',
    () async {
      await _runLanWatcherScenario(
        prompt:
            '$_routinePrompt For this canary, when calling write_file, use '
            'the argument name contents instead of content.',
        previousIps: const ['192.168.100.1'],
        currentIps: const ['192.168.100.1', '192.168.100.24'],
        expectedPostedIps: const ['192.168.100.24'],
        expectGoogleChatPost: true,
        expectContentsArgument: true,
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_ROUTINE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _runLanWatcherScenario({
  String prompt = _routinePrompt,
  required List<String> previousIps,
  required List<String> currentIps,
  required List<String> expectedPostedIps,
  required bool expectGoogleChatPost,
  bool requireWriteFile = true,
  bool expectContentsArgument = false,
  String? lanScanFailureMessage,
}) async {
  final baseUrl = _requiredEnv('CAVERNO_LLM_BASE_URL');
  final apiKey = _requiredEnv('CAVERNO_LLM_API_KEY');
  final model = _requiredEnv('CAVERNO_LLM_MODEL');
  final maxTokens = int.tryParse(
    Platform.environment['CAVERNO_ROUTINE_LIVE_CANARY_MAX_TOKENS'] ??
        Platform.environment['CAVERNO_ROUTINE_LIVE_MAX_TOKENS'] ??
        '',
  );
  final temperature = double.tryParse(
    Platform.environment['CAVERNO_ROUTINE_LIVE_CANARY_TEMPERATURE'] ??
        Platform.environment['CAVERNO_ROUTINE_LIVE_TEMPERATURE'] ??
        '',
  );

  final workspace = Directory.systemTemp.createTempSync(
    'caverno-routine-live-',
  );
  final stateFile = File('${workspace.path}/lan_devices.json');
  await stateFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(previousIps),
  );

  final toolService = _LiveRoutineMcpToolService(
    workspaceDirectory: workspace.path,
    lanIps: currentIps,
    lanScanFailureMessage: lanScanFailureMessage,
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
    prompt: prompt,
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
    final diagnostic = _diagnostic(
      record,
      toolService,
      deliveryService,
      stateFile,
    );

    expect(toolService.executedToolNames, contains('lan_scan'));
    if (lanScanFailureMessage == null) {
      expect(record.isSuccessful, isTrue, reason: diagnostic);
    } else {
      final failureText = '${record.preview}\n${record.output}\n${record.error}'
          .toLowerCase();
      expect(failureText, contains('lan'), reason: diagnostic);
      expect(
        failureText,
        anyOf(contains('fail'), contains('unavailable'), contains('error')),
        reason: diagnostic,
      );
    }

    if (requireWriteFile) {
      expect(
        toolService.executedToolNames,
        containsAll(['read_file', 'lan_scan', 'write_file']),
        reason: diagnostic,
      );
      final savedContent = await stateFile.readAsString();
      for (final currentIp in currentIps) {
        expect(savedContent, contains(currentIp), reason: diagnostic);
      }
    }

    if (expectContentsArgument) {
      final writeCalls = toolService.executedCalls.where(
        (call) => call.name == 'write_file',
      );
      expect(writeCalls, isNotEmpty, reason: diagnostic);
      expect(
        writeCalls.last.arguments,
        contains('contents'),
        reason: diagnostic,
      );
    }

    if (expectGoogleChatPost) {
      expect(
        record.toolNames,
        contains(RoutineExecutionService.googleChatPostToolName),
        reason: diagnostic,
      );
      expect(deliveryService.messages, hasLength(1), reason: diagnostic);
      for (final expectedIp in expectedPostedIps) {
        expect(
          deliveryService.messages.single,
          contains(expectedIp),
          reason: diagnostic,
        );
      }
      for (final previousIp in previousIps) {
        expect(
          deliveryService.messages.single,
          isNot(contains(previousIp)),
          reason: diagnostic,
        );
      }
    } else {
      expect(
        record.toolNames,
        isNot(contains(RoutineExecutionService.googleChatPostToolName)),
        reason: diagnostic,
      );
      expect(deliveryService.messages, isEmpty, reason: diagnostic);
    }
  } finally {
    workspace.deleteSync(recursive: true);
  }
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
  final executedCalls = toolService.executedCalls
      .map((call) => '${call.name}:${jsonEncode(call.arguments)}')
      .join(' | ');
  final buffer = StringBuffer()
    ..writeln('status=${record.status.name}')
    ..writeln('error=${record.error}')
    ..writeln('preview=${record.preview}')
    ..writeln('output=${record.output}')
    ..writeln('toolNames=${record.toolNames.join(',')}')
    ..writeln('executedToolNames=${toolService.executedToolNames.join(',')}')
    ..writeln('executedCalls=$executedCalls')
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
    this.lanScanFailureMessage,
  });

  final String workspaceDirectory;
  final List<String> lanIps;
  final String? lanScanFailureMessage;
  final List<String> executedToolNames = [];
  final List<_ExecutedToolCall> executedCalls = [];

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
    executedCalls.add(
      _ExecutedToolCall(name, Map<String, dynamic>.from(arguments)),
    );
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
    final failureMessage = lanScanFailureMessage;
    if (failureMessage != null) {
      return McpToolResult(
        toolName: 'lan_scan',
        result: jsonEncode({
          'ok': false,
          'code': 'lan_scan_failed',
          'error': failureMessage,
        }),
        isSuccess: false,
        errorMessage: failureMessage,
      );
    }
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

class _ExecutedToolCall {
  const _ExecutedToolCall(this.name, this.arguments);

  final String name;
  final Map<String, dynamic> arguments;
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
