import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/google_chat_delivery_service.dart';
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
    googleChatDeliveryService: ref.watch(googleChatDeliveryServiceProvider),
    mcpToolService: ref.watch(mcpToolServiceProvider),
    settings: ref.watch(settingsNotifierProvider),
  );
});

class RoutineExecutionService {
  RoutineExecutionService({
    required ChatDataSource dataSource,
    GoogleChatDeliveryService? googleChatDeliveryService,
    McpToolService? mcpToolService,
    required AppSettings settings,
    RoutineToolRunner? toolRunner,
  }) : _dataSource = dataSource,
       _googleChatDeliveryService = googleChatDeliveryService,
       _mcpToolService = mcpToolService,
       _toolRunner = toolRunner ?? RoutineToolRunner(dataSource: dataSource),
       _settings = settings;

  static const String googleChatPostToolName = 'routine_google_chat_post';
  static const String _googleChatSourceLabel = 'Google Chat';

  static Map<String, dynamic> get _googleChatPostToolDefinition => {
    'type': 'function',
    RoutineToolPolicy.routineToolDefinitionKey: true,
    McpToolEntity.openAiSourceLabelKey: _googleChatSourceLabel,
    'function': {
      'name': googleChatPostToolName,
      'description':
          'Post a concise routine-created message to the configured Google '
          'Chat incoming webhook. Use this only when the routine prompt asks '
          'for a conditional Google Chat notification.',
      'parameters': {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'Message text to post to Google Chat.',
          },
        },
        'required': ['text'],
      },
    },
  };

  final ChatDataSource _dataSource;
  final GoogleChatDeliveryService? _googleChatDeliveryService;
  final McpToolService? _mcpToolService;
  final RoutineToolRunner _toolRunner;
  final AppSettings _settings;
  final Uuid _uuid = const Uuid();
  static const int _maxStoredOutputLength = 24000;
  static const int _maxStoredToolArgumentsLength = 4000;
  static const int _maxStoredToolResultLength = 12000;

  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    final startedAt = DateTime.now();

    try {
      final allowedTools = _allowedRoutineTools(routine);
      final systemPrompt = _buildRoutineSystemPrompt(
        now: startedAt,
        routine: routine,
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
        routine: routine,
        allowedTools: allowedTools,
      );
      final output = RoutineScheduleService.truncateOutput(
        executionResult.output,
        maxLength: _maxStoredOutputLength,
      );
      final visibleOutput = RoutineScheduleService.visibleOutput(output);
      final preview = RoutineScheduleService.summarizeOutput(output);
      final toolNames = _toolNamesFromResults(executionResult.toolResults);
      final toolCalls = _toolCallsFromResults(executionResult.toolResults);
      final toolSourceLabels = _toolSourceLabelsFromResults(
        executionResult.toolResults,
        allowedTools,
      );
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(startedAt).inMilliseconds;

      if (visibleOutput.isEmpty) {
        final failureMessage = executionResult.wasTruncated
            ? 'Routine response was truncated before producing visible output.'
            : 'Routine completed without any visible output.';
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
          toolCalls: toolCalls,
          toolSourceLabels: toolSourceLabels,
          preview: failureMessage,
          output: output,
          error: failureMessage,
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
        toolCalls: toolCalls,
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
    required Routine routine,
    required List<Map<String, dynamic>> allowedTools,
  }) {
    final toolNames = _toolNamesFromDefinitions(allowedTools);
    final basePrompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      languageCode: _resolveLanguageCode(),
      toolNames: toolNames,
    );

    final routineGuidance = _buildRoutineGuidance(
      routine: routine,
      allowedToolNames: toolNames.toSet(),
    );

    if (allowedTools.isEmpty && routineGuidance.isEmpty) {
      return basePrompt;
    }

    return [
      basePrompt,
      if (allowedTools.isNotEmpty)
        'Routine execution context: this is an unattended scheduled/manual routine. '
            'When the routine prompt asks for diagnostics, lookup, or inspection '
            'that requires available tools, call the relevant tools directly. '
            'Do not ask the user for confirmation before routine tool use. '
            'Do not answer with only a proposed tool workflow when the available tools '
            'can satisfy the request. Provide a concise final result after tool evidence '
            'is collected.',
      ...routineGuidance,
    ].join('\n');
  }

  Future<RoutineToolExecutionResult> _executeRoutine({
    required List<Message> messages,
    required Routine routine,
    required List<Map<String, dynamic>> allowedTools,
  }) async {
    if (allowedTools.isEmpty) {
      final result = await _dataSource.createChatCompletion(
        messages: messages,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );
      return RoutineToolExecutionResult(
        output: result.content,
        wasTruncated: _isCompletionTruncated(result.finishReason),
      );
    }

    final allowedToolNames = _toolNamesFromDefinitions(allowedTools).toSet();
    return _toolRunner.execute(
      messages: messages,
      tools: allowedTools,
      dispatchToolCall: (toolCall) => _dispatchRoutineToolCall(
        toolCall,
        routine: routine,
        allowedToolNames: allowedToolNames,
      ),
      model: _settings.model,
      temperature: _settings.temperature,
      maxTokens: _settings.maxTokens,
    );
  }

  bool _isCompletionTruncated(String finishReason) {
    final normalized = finishReason.trim().toLowerCase();
    return normalized == 'length' || normalized == 'max_tokens';
  }

  List<String> _buildRoutineGuidance({
    required Routine routine,
    required Set<String> allowedToolNames,
  }) {
    final guidance = <String>[];
    if (routine.hasWorkspaceDirectory) {
      guidance.add(
        'Routine workspace directory: ${routine.trimmedWorkspaceDirectory}. '
        'Use this directory for persistent routine state files. Relative paths '
        'passed to workspace file tools are resolved against this directory.',
      );
      guidance.add(
        'When the task needs to compare current results with previous runs, '
        'read and update state files in the routine workspace.',
      );
    }
    if (routine.hasWorkspaceWriteAccess) {
      guidance.add(
        'Workspace write access is enabled for write_file and edit_file only, '
        'and only inside the routine workspace directory.',
      );
    }
    if (allowedToolNames.contains(googleChatPostToolName)) {
      guidance.add(
        'Use $googleChatPostToolName only when the routine prompt condition '
        'for a Google Chat notification is satisfied. Keep the message concise.',
      );
    }
    return guidance;
  }

  List<Map<String, dynamic>> _allowedRoutineTools(Routine routine) {
    if (!routine.toolsEnabled) {
      return const <Map<String, dynamic>>[];
    }
    final extraDefinitions = <Map<String, dynamic>>[
      if (_settings.hasGoogleChatWebhook && routine.allowsPromptGoogleChatPost)
        _googleChatPostToolDefinition,
    ];
    return RoutineToolPolicy.filterAllowedToolDefinitions(
      _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
      allowWorkspaceWrites: routine.hasWorkspaceWriteAccess,
      extraDefinitions: extraDefinitions,
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
    required Routine routine,
    required Set<String> allowedToolNames,
  }) async {
    if (!allowedToolNames.contains(toolCall.name)) {
      return RoutineToolPolicy.buildDeniedResult(toolCall);
    }

    if (toolCall.name == googleChatPostToolName) {
      return _postRoutineGoogleChatMessage(toolCall);
    }

    final toolService = _mcpToolService;
    if (toolService == null) {
      return RoutineToolPolicy.buildUnavailableResult(toolCall);
    }

    final scopedArgumentsResult = _scopedWorkspaceArguments(
      routine: routine,
      toolCall: toolCall,
    );
    if (scopedArgumentsResult.deniedResult != null) {
      return scopedArgumentsResult.deniedResult!;
    }

    return toolService.executeTool(
      name: toolCall.name,
      arguments: scopedArgumentsResult.arguments,
    );
  }

  Future<McpToolResult> _postRoutineGoogleChatMessage(
    ToolCallInfo toolCall,
  ) async {
    final deliveryService = _googleChatDeliveryService;
    if (deliveryService == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'error': 'Google Chat delivery service is unavailable.',
          'code': 'tool_unavailable',
          'reason': 'routine_google_chat_service_unavailable',
        }),
        isSuccess: false,
        errorMessage: 'Google Chat delivery service is unavailable',
      );
    }

    final text = (toolCall.arguments['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'error': 'text is required',
          'code': 'invalid_arguments',
          'reason': 'routine_google_chat_text_required',
        }),
        isSuccess: false,
        errorMessage: 'Google Chat message text is required',
      );
    }

    final result = await deliveryService.sendMessage(
      webhookUrl: _settings.normalizedGoogleChatWebhookUrl,
      text: text,
    );

    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'delivered': result.isSuccessful,
        'message': result.message,
        if (result.deliveredAt != null)
          'delivered_at': result.deliveredAt!.toIso8601String(),
      }),
      isSuccess: result.isSuccessful,
      errorMessage: result.isSuccessful ? null : result.message,
    );
  }

  _ScopedRoutineArguments _scopedWorkspaceArguments({
    required Routine routine,
    required ToolCallInfo toolCall,
  }) {
    final arguments = _normalizeRoutineToolArguments(
      toolCall.name,
      toolCall.arguments,
    );

    if (!RoutineToolPolicy.isWorkspacePathToolName(toolCall.name)) {
      return _ScopedRoutineArguments(arguments: arguments);
    }

    final workspaceDirectory = routine.trimmedWorkspaceDirectory;
    final rawPath = (arguments['path'] as String?)?.trim() ?? '';
    if (RoutineToolPolicy.isWorkspaceWriteToolName(toolCall.name) &&
        (!routine.hasWorkspaceWriteAccess || rawPath.isEmpty)) {
      return _ScopedRoutineArguments(
        arguments: arguments,
        deniedResult: RoutineToolPolicy.buildWorkspaceWriteDeniedResult(
          toolCall,
          workspaceDirectory: workspaceDirectory,
          attemptedPath: rawPath,
        ),
      );
    }

    if (!routine.hasWorkspaceDirectory) {
      return _ScopedRoutineArguments(arguments: arguments);
    }

    final workspacePath = _normalizeDirectoryPath(workspaceDirectory);
    final targetPath = rawPath.isEmpty
        ? (RoutineToolPolicy.isWorkspaceReadToolName(toolCall.name)
              ? workspacePath
              : rawPath)
        : _resolveWorkspacePath(workspacePath: workspacePath, rawPath: rawPath);

    if (RoutineToolPolicy.isWorkspaceWriteToolName(toolCall.name) &&
        (!_isInsideOrSame(workspacePath, targetPath) ||
            _existingPathEscapesWorkspace(
              workspacePath: workspacePath,
              targetPath: targetPath,
            ))) {
      return _ScopedRoutineArguments(
        arguments: arguments,
        deniedResult: RoutineToolPolicy.buildWorkspaceWriteDeniedResult(
          toolCall,
          workspaceDirectory: workspacePath,
          attemptedPath: rawPath,
        ),
      );
    }

    return _ScopedRoutineArguments(
      arguments: rawPath.isEmpty && toolCall.name == 'read_file'
          ? arguments
          : {...arguments, 'path': targetPath},
    );
  }

  Map<String, dynamic> _normalizeRoutineToolArguments(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final normalizedArguments = <String, dynamic>{...arguments};
    if (toolName == 'write_file') {
      final content = normalizedArguments['content'];
      if (content != null && content is! String) {
        normalizedArguments['content'] = _stringifyWriteFileContent(content);
      }

      final normalizedContent = (normalizedArguments['content'] as String?)
          ?.trim();
      final contents = normalizedArguments['contents'];
      if ((normalizedContent == null || normalizedContent.isEmpty) &&
          contents != null) {
        final normalizedContents = _stringifyWriteFileContent(contents);
        if (normalizedContents.trim().isNotEmpty) {
          normalizedArguments['content'] = normalizedContents;
        }
      }
    }
    return normalizedArguments;
  }

  String _stringifyWriteFileContent(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    if (value is List || value is Map) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value.toString();
  }

  String _resolveWorkspacePath({
    required String workspacePath,
    required String rawPath,
  }) {
    if (_isAbsolutePath(rawPath)) {
      return _normalizeFilePath(rawPath);
    }
    return _normalizeFilePath(
      '$workspacePath${Platform.pathSeparator}$rawPath',
    );
  }

  String _normalizeDirectoryPath(String path) {
    final normalized = _normalizePath(path, isDirectory: true);
    if (FileSystemEntity.typeSync(normalized, followLinks: true) ==
        FileSystemEntityType.notFound) {
      return normalized;
    }

    try {
      return _normalizePath(
        Directory(normalized).resolveSymbolicLinksSync(),
        isDirectory: true,
      );
    } on FileSystemException {
      return normalized;
    }
  }

  String _normalizeFilePath(String path) {
    return _normalizePath(path, isDirectory: false);
  }

  String _normalizePath(String path, {required bool isDirectory}) {
    final absolutePath = isDirectory
        ? Directory(path).absolute.path
        : File(path).absolute.path;
    final normalizedPath = Uri.file(absolutePath).normalizePath().toFilePath();
    if (normalizedPath.length > 1 &&
        normalizedPath.endsWith(Platform.pathSeparator)) {
      return normalizedPath.substring(0, normalizedPath.length - 1);
    }
    return normalizedPath;
  }

  bool _isAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  bool _isInsideOrSame(String workspacePath, String targetPath) {
    if (targetPath == workspacePath) {
      return true;
    }
    final prefix = workspacePath.endsWith(Platform.pathSeparator)
        ? workspacePath
        : '$workspacePath${Platform.pathSeparator}';
    return targetPath.startsWith(prefix);
  }

  bool _existingPathEscapesWorkspace({
    required String workspacePath,
    required String targetPath,
  }) {
    final resolvedTarget = _resolveExistingPath(targetPath);
    if (resolvedTarget != null &&
        !_isInsideOrSame(workspacePath, resolvedTarget)) {
      return true;
    }

    var parentPath = _normalizePath(
      File(targetPath).parent.path,
      isDirectory: true,
    );
    while (_isInsideOrSame(workspacePath, parentPath)) {
      final resolvedParent = _resolveExistingPath(parentPath);
      if (resolvedParent != null &&
          !_isInsideOrSame(workspacePath, resolvedParent)) {
        return true;
      }
      final nextParentPath = _normalizePath(
        Directory(parentPath).parent.path,
        isDirectory: true,
      );
      if (nextParentPath == parentPath) {
        break;
      }
      parentPath = nextParentPath;
    }
    return false;
  }

  String? _resolveExistingPath(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }

    try {
      final resolvedPath = switch (type) {
        FileSystemEntityType.directory => Directory(
          path,
        ).resolveSymbolicLinksSync(),
        _ => File(path).resolveSymbolicLinksSync(),
      };
      return _normalizeFilePath(resolvedPath);
    } on FileSystemException {
      return _normalizeFilePath(path);
    }
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

  List<RoutineRunToolCall> _toolCallsFromResults(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults
        .map(
          (toolResult) => RoutineRunToolCall(
            id: toolResult.id,
            name: toolResult.name,
            arguments: _encodeToolArguments(toolResult.arguments),
            result: RoutineScheduleService.truncateOutput(
              toolResult.result,
              maxLength: _maxStoredToolResultLength,
            ),
          ),
        )
        .toList(growable: false);
  }

  String _encodeToolArguments(Map<String, dynamic> arguments) {
    final encoded = const JsonEncoder.withIndent('  ').convert(arguments);
    return RoutineScheduleService.truncateOutput(
      encoded,
      maxLength: _maxStoredToolArgumentsLength,
    );
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

class _ScopedRoutineArguments {
  const _ScopedRoutineArguments({required this.arguments, this.deniedResult});

  final Map<String, dynamic> arguments;
  final McpToolResult? deniedResult;
}
