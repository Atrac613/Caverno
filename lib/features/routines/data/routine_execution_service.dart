import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/types/assistant_mode.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/chat_remote_datasource.dart';
import '../../chat/data/datasources/mcp_tool_service.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/services/system_prompt_builder.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../settings/domain/entities/app_settings.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/entities/routine.dart';
import '../domain/services/routine_schedule_service.dart';
import '../domain/services/routine_tool_policy.dart';
import 'routine_tool_runner.dart';

final routineExecutionServiceProvider = Provider<RoutineExecutionService>((
  ref,
) {
  return RoutineExecutionService(
    dataSource: ref.watch(chatRemoteDataSourceProvider),
    mcpToolService: ref.watch(mcpToolServiceProvider),
    settings: ref.watch(settingsNotifierProvider),
  );
});

class RoutineExecutionService {
  RoutineExecutionService({
    required ChatDataSource dataSource,
    McpToolService? mcpToolService,
    required AppSettings settings,
    RoutineToolRunner? toolRunner,
  }) : _dataSource = dataSource,
       _mcpToolService = mcpToolService,
       _toolRunner = toolRunner ?? RoutineToolRunner(dataSource: dataSource),
       _settings = settings;

  final ChatDataSource _dataSource;
  final McpToolService? _mcpToolService;
  final RoutineToolRunner _toolRunner;
  final AppSettings _settings;
  final Uuid _uuid = const Uuid();

  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    final startedAt = DateTime.now();

    try {
      final systemPrompt = SystemPromptBuilder.build(
        now: startedAt,
        assistantMode: AssistantMode.general,
        languageCode: _resolveLanguageCode(),
      );
      final messages = [
        Message(
          id: 'routine_system',
          content: systemPrompt,
          role: MessageRole.system,
          timestamp: startedAt,
        ),
        Message(
          id: 'routine_user',
          content: routine.trimmedPrompt,
          role: MessageRole.user,
          timestamp: startedAt,
        ),
      ];

      final executionResult = await _executeRoutine(
        routine: routine,
        messages: messages,
      );
      final output = RoutineScheduleService.truncateOutput(
        executionResult.output,
      );
      final preview = RoutineScheduleService.summarizeOutput(output);
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(startedAt).inMilliseconds;

      if (output.isEmpty) {
        return RoutineRunRecord(
          id: _uuid.v4(),
          startedAt: startedAt,
          finishedAt: finishedAt,
          status: RoutineRunStatus.failed,
          trigger: trigger,
          durationMs: durationMs,
          usedTools: executionResult.toolResults.isNotEmpty,
          toolCallCount: executionResult.toolResults.length,
          toolNames: _toolNamesFromResults(executionResult.toolResults),
          preview: 'Routine completed without any visible output.',
          error: 'Routine completed without any visible output.',
        );
      }

      return RoutineRunRecord(
        id: _uuid.v4(),
        startedAt: startedAt,
        finishedAt: finishedAt,
        status: RoutineRunStatus.completed,
        trigger: trigger,
        durationMs: durationMs,
        usedTools: executionResult.toolResults.isNotEmpty,
        toolCallCount: executionResult.toolResults.length,
        toolNames: _toolNamesFromResults(executionResult.toolResults),
        preview: preview,
        output: output,
      );
    } catch (error) {
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(startedAt).inMilliseconds;
      final message = error.toString().trim();

      return RoutineRunRecord(
        id: _uuid.v4(),
        startedAt: startedAt,
        finishedAt: finishedAt,
        status: RoutineRunStatus.failed,
        trigger: trigger,
        durationMs: durationMs,
        preview: message,
        error: message,
      );
    }
  }

  String _resolveLanguageCode() {
    final preference = _settings.language.trim().toLowerCase();
    if (preference == 'ja' || preference == 'en') {
      return preference;
    }
    return 'en';
  }

  Future<RoutineToolExecutionResult> _executeRoutine({
    required Routine routine,
    required List<Message> messages,
  }) async {
    final allowedTools = routine.toolsEnabled
        ? RoutineToolPolicy.filterAllowedToolDefinitions(
            _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
          )
        : const <Map<String, dynamic>>[];

    if (allowedTools.isEmpty) {
      final result = await _dataSource.createChatCompletion(
        messages: messages,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );
      return RoutineToolExecutionResult(output: result.content);
    }

    return _toolRunner.execute(
      messages: messages,
      tools: allowedTools,
      dispatchToolCall: _dispatchRoutineToolCall,
      model: _settings.model,
      temperature: _settings.temperature,
      maxTokens: _settings.maxTokens,
    );
  }

  Future<McpToolResult> _dispatchRoutineToolCall(ToolCallInfo toolCall) async {
    final toolService = _mcpToolService;
    if (toolService == null) {
      return RoutineToolPolicy.buildUnavailableResult(toolCall);
    }
    if (!RoutineToolPolicy.isAllowedToolName(toolCall.name)) {
      return RoutineToolPolicy.buildDeniedResult(toolCall);
    }

    return toolService.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
  }

  List<String> _toolNamesFromResults(List<ToolResultInfo> toolResults) {
    final names = <String>[];
    for (final toolResult in toolResults) {
      if (!names.contains(toolResult.name)) {
        names.add(toolResult.name);
      }
    }
    return names;
  }
}
