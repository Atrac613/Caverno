import 'dart:convert';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs live harness probes with safe tool execution', () async {
    final dataSource = _FakeDiagnosticDataSource();
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: true),
      chatDataSource: dataSource,
      mcpToolService: McpToolService(),
    );
    final updates = <LiveLlmDiagnosticReport>[];

    final report = await service.run(onReport: updates.add);

    expect(updates.length, greaterThan(2));
    expect(report.overallStatus, LiveLlmDiagnosticStatus.passed);
    expect(report.toolCatalog.totalToolCount, greaterThan(0));
    expect(report.toolCatalog.toolSearchEnabled, isTrue);
    expect(dataSource.toolResultFollowUpCount, 1);
    expect(
      report.results
          .where((result) => result.status == LiveLlmDiagnosticStatus.passed)
          .length,
      6,
    );
    expect(
      report.results
          .where((result) => result.status == LiveLlmDiagnosticStatus.skipped)
          .length,
      2,
    );
  });

  test('skips tool probes when MCP tools are disabled', () async {
    final service = LiveLlmDiagnosticService(
      settings: _settings(mcpEnabled: false),
      chatDataSource: _FakeDiagnosticDataSource(),
      mcpToolService: McpToolService(),
    );

    final report = await service.run();

    expect(report.toolCatalog.totalToolCount, 0);
    expect(
      _result(report, 'instruction_echo').status,
      LiveLlmDiagnosticStatus.passed,
    );
    expect(
      _result(report, 'narrow_tool_call').status,
      LiveLlmDiagnosticStatus.skipped,
    );
    expect(
      _result(report, 'remote_mcp_exposure').status,
      LiveLlmDiagnosticStatus.skipped,
    );
  });

  test(
    'uses textual tool calls for Apple Foundation Models diagnostics',
    () async {
      final dataSource = _FakeDiagnosticDataSource(textToolCalls: true);
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
          baseUrl: 'http://127.0.0.1:1234/v1',
          model: 'qwen3.6-27b-mtp-vision',
        ),
        chatDataSource: dataSource,
        mcpToolService: McpToolService(),
      );

      final report = await service.run();

      expect(report.baseUrl, 'apple-foundation-models://local');
      expect(report.model, AppSettings.appleFoundationModelsModelId);
      expect(dataSource.requestedModels, [
        for (var i = 0; i < 5; i += 1) AppSettings.appleFoundationModelsModelId,
      ]);
      expect(dataSource.toolResultFollowUpCount, 0);
      expect(
        _result(report, 'instruction_echo').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.passed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
      expect(
        _result(report, 'subagent_recognition').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test(
    'reports unsupported Foundation Models language errors as probe failures',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: _UnsupportedLanguageDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run();
      final result = _result(report, 'instruction_echo');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, contains('rejected this prompt language'));
      expect(result.details, contains('unsupportedLanguageOrLocale'));
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );

  test(
    'reports unavailable Foundation Models preflight as probe failures',
    () async {
      final service = LiveLlmDiagnosticService(
        settings: _settings(
          mcpEnabled: true,
          llmProvider: LlmProvider.appleFoundationModels,
        ),
        chatDataSource: _UnavailableFoundationModelsDataSource(),
        mcpToolService: McpToolService(),
      );

      final report = await service.run();
      final result = _result(report, 'instruction_echo');

      expect(result.status, LiveLlmDiagnosticStatus.failed);
      expect(result.summary, contains('not available'));
      expect(result.details, contains('preflight'));
      expect(result.details, contains('modelNotReady'));
      expect(
        _result(report, 'foundation_models_language_matrix').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'narrow_tool_call').status,
        LiveLlmDiagnosticStatus.failed,
      );
      expect(
        _result(report, 'tool_result_integration').status,
        LiveLlmDiagnosticStatus.skipped,
      );
    },
  );
}

AppSettings _settings({
  required bool mcpEnabled,
  LlmProvider llmProvider = LlmProvider.openAiCompatible,
  String baseUrl = 'http://localhost:1234/v1',
  String model = 'test-model',
}) {
  return AppSettings.defaults().copyWith(
    llmProvider: llmProvider,
    baseUrl: baseUrl,
    model: model,
    mcpEnabled: mcpEnabled,
    mcpUrl: '',
    mcpUrls: const <String>[],
    mcpServers: const <McpServerConfig>[],
  );
}

LiveLlmDiagnosticProbeResult _result(
  LiveLlmDiagnosticReport report,
  String id,
) {
  return report.results.singleWhere((result) => result.id == id);
}

class _FakeDiagnosticDataSource implements ChatDataSource {
  _FakeDiagnosticDataSource({this.textToolCalls = false});

  final bool textToolCalls;
  int toolResultFollowUpCount = 0;
  final List<String?> requestedModels = [];

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    final user = messages.last.content;
    if (user.contains('Return exactly this JSON object')) {
      return ChatCompletionResult(
        content:
            '{"probe":"instruction_echo","status":"ok","marker":"CAVERNO_LIVE_DIAGNOSTIC"}',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_EN')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_EN',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_JA')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_JA',
        finishReason: 'stop',
      );
    }
    if (user.contains('CAVERNO_FM_LANG_TOOL')) {
      return ChatCompletionResult(
        content: 'CAVERNO_FM_LANG_TOOL',
        finishReason: 'stop',
      );
    }
    if (user.contains('tool catalog search tool')) {
      return _toolCall('tool_search', {
        'query': 'delegate focused sub-task child agent',
        'max_results': 8,
      });
    }
    if (user.contains('spawn_subagent tool call')) {
      return _toolCall('spawn_subagent', {
        'description': 'Diagnostic subagent marker summary',
        'prompt': 'Summarize the marker CAVERNO_SUBAGENT_DIAGNOSTIC and stop.',
        'background': true,
      });
    }
    if (user.contains('get_current_datetime')) {
      return _toolCall('get_current_datetime', const <String, dynamic>{});
    }
    return ChatCompletionResult(
      content: 'Unhandled fake prompt',
      finishReason: 'stop',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    return createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: toolCallId,
          name: toolName,
          arguments: jsonDecode(toolArguments) as Map<String, dynamic>,
          result: toolResult,
        ),
      ],
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    toolResultFollowUpCount += 1;
    final payload =
        jsonDecode(toolResults.single.result) as Map<String, dynamic>;
    final relativeDates = payload['relative_dates'] as Map<String, dynamic>;
    return ChatCompletionResult(
      content: jsonEncode({
        'probe': 'datetime_tool_result',
        'marker': 'CAVERNO_TOOL_RESULT_OK',
        'today': relativeDates['today'],
        'timezone': payload['timezone'],
      }),
      finishReason: 'stop',
    );
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  ChatCompletionResult _toolCall(String name, Map<String, dynamic> arguments) {
    if (textToolCalls) {
      return ChatCompletionResult(
        content:
            '<tool_use>${jsonEncode({'name': name, 'arguments': arguments})}</tool_use>',
        finishReason: 'stop',
      );
    }
    return ChatCompletionResult(
      content: '',
      toolCalls: [
        ToolCallInfo(id: 'call-$name', name: name, arguments: arguments),
      ],
      finishReason: 'tool_calls',
    );
  }
}

class _UnsupportedLanguageDataSource implements ChatDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    throw Exception(
      'unsupportedLanguageOrLocale(GenerationError.Context(debugDescription: "Unsupported language."))',
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _UnavailableFoundationModelsDataSource
    extends _UnsupportedLanguageDataSource {
  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    throw AppleFoundationModelsException.unavailable(
      const AppleFoundationModelsAvailability(
        isAvailable: false,
        status: 'unavailable',
        reason: 'modelNotReady',
      ),
    );
  }
}
