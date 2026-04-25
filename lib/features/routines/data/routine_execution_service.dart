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
      final allowedTools = _allowedRoutineTools(routine);
      final systemPrompt = _buildRoutineSystemPrompt(
        now: startedAt,
        allowedTools: allowedTools,
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
        messages: messages,
        allowedTools: allowedTools,
      );
      final output = RoutineScheduleService.truncateOutput(
        executionResult.output,
      );
      final preview = RoutineScheduleService.summarizeOutput(output);
      final toolNames = _toolNamesFromResults(executionResult.toolResults);
      final toolSourceLabels = _toolSourceLabelsFromResults(
        executionResult.toolResults,
        allowedTools,
      );
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
          toolNames: toolNames,
          toolSourceLabels: toolSourceLabels,
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
        toolNames: toolNames,
        toolSourceLabels: toolSourceLabels,
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

  String _buildRoutineSystemPrompt({
    required DateTime now,
    required List<Map<String, dynamic>> allowedTools,
  }) {
    final toolNames = _toolNamesFromDefinitions(allowedTools);
    final basePrompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      languageCode: _resolveLanguageCode(),
      toolNames: toolNames,
    );

    if (allowedTools.isEmpty) {
      return basePrompt;
    }

    return [
      basePrompt,
      'Routine execution context: this is an unattended scheduled/manual routine. '
          'When the routine prompt asks for diagnostics, lookup, or inspection '
          'that requires available read-only tools, call the relevant tools directly. '
          'Do not ask the user for confirmation before read-only routine tool use. '
          'Do not answer with only a proposed tool workflow when the available tools '
          'can satisfy the request. Provide a concise final result after tool evidence '
          'is collected.',
    ].join('\n');
  }

  Future<RoutineToolExecutionResult> _executeRoutine({
    required List<Message> messages,
    required List<Map<String, dynamic>> allowedTools,
  }) async {
    if (allowedTools.isEmpty) {
      final result = await _dataSource.createChatCompletion(
        messages: messages,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );
      return RoutineToolExecutionResult(output: result.content);
    }

    final allowedToolNames = _toolNamesFromDefinitions(allowedTools).toSet();
    return _toolRunner.execute(
      messages: messages,
      tools: allowedTools,
      dispatchToolCall: (toolCall) => _dispatchRoutineToolCall(
        toolCall,
        allowedToolNames: allowedToolNames,
      ),
      model: _settings.model,
      temperature: _settings.temperature,
      maxTokens: _settings.maxTokens,
    );
  }

  List<Map<String, dynamic>> _allowedRoutineTools(Routine routine) {
    if (!routine.toolsEnabled) {
      return const <Map<String, dynamic>>[];
    }
    return RoutineToolPolicy.filterAllowedToolDefinitions(
      _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
    );
  }

  List<String> _toolNamesFromDefinitions(List<Map<String, dynamic>> tools) {
    return tools
        .map((tool) => (tool['function'] as Map?)?['name'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<McpToolResult> _dispatchRoutineToolCall(
    ToolCallInfo toolCall, {
    required Set<String> allowedToolNames,
  }) async {
    final toolService = _mcpToolService;
    if (toolService == null) {
      return RoutineToolPolicy.buildUnavailableResult(toolCall);
    }
    if (!allowedToolNames.contains(toolCall.name)) {
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

  Map<String, String> _toolSourceLabelsFromResults(
    List<ToolResultInfo> toolResults,
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    final labelsByName = <String, String>{};
    for (final tool in toolDefinitions) {
      final function = tool['function'];
      final name = function is Map ? function['name'] as String? : null;
      final sourceLabel = tool[McpToolEntity.openAiSourceLabelKey] as String?;
      if (name != null &&
          name.isNotEmpty &&
          sourceLabel != null &&
          sourceLabel.trim().isNotEmpty) {
        labelsByName[name] = sourceLabel.trim();
      }
    }

    final executedLabels = <String, String>{};
    for (final toolResult in toolResults) {
      final sourceLabel = labelsByName[toolResult.name];
      if (sourceLabel != null && sourceLabel.isNotEmpty) {
        executedLabels[toolResult.name] = sourceLabel;
      }
    }
    return executedLabels;
  }
}
