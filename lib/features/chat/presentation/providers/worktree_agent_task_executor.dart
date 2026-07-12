import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_request_temperature_policy.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/subagent_task.dart';
import '../../domain/entities/worktree_agent_task.dart';
import '../../domain/services/subagent_execution_service.dart';
import 'chat_notifier.dart';
import 'mcp_tool_provider.dart';
import 'worktree_agent_task_registry_notifier.dart';
import 'worktree_agent_verification_runner.dart';

class WorktreeAgentTaskExecutionContext {
  const WorktreeAgentTaskExecutionContext({required this.task});

  final WorktreeAgentTask task;

  String get taskId => task.id;

  String get title => task.title;

  String get prompt => task.prompt;

  String get worktreePath => task.worktreePath;

  String get branchName => task.branchName;

  String get checkpointLineageId => task.checkpointLineageId;

  String get endpointId => task.endpointId;

  String get verificationCommand => task.verificationCommand;
}

class WorktreeAgentTaskExecutionOutcome {
  const WorktreeAgentTaskExecutionOutcome({
    required this.resultSummary,
    this.verifiedGreen = false,
    this.verificationSummary = '',
  });

  final String resultSummary;
  final bool verifiedGreen;
  final String verificationSummary;
}

class WorktreeAgentTaskExecutionResult {
  const WorktreeAgentTaskExecutionResult({
    required this.success,
    required this.taskId,
    this.resultSummary = '',
    this.verifiedGreen = false,
    this.verificationSummary = '',
    this.errorMessage,
  });

  const WorktreeAgentTaskExecutionResult.succeeded({
    required String taskId,
    required String resultSummary,
    required bool verifiedGreen,
    required String verificationSummary,
  }) : this(
         success: true,
         taskId: taskId,
         resultSummary: resultSummary,
         verifiedGreen: verifiedGreen,
         verificationSummary: verificationSummary,
       );

  const WorktreeAgentTaskExecutionResult.failed({
    required String taskId,
    required String errorMessage,
  }) : this(success: false, taskId: taskId, errorMessage: errorMessage);

  final bool success;
  final String taskId;
  final String resultSummary;
  final bool verifiedGreen;
  final String verificationSummary;
  final String? errorMessage;
}

typedef WorktreeAgentTaskExecutionDelegate =
    Future<WorktreeAgentTaskExecutionOutcome> Function(
      WorktreeAgentTaskExecutionContext context,
    );

final worktreeAgentTaskExecutionDelegateProvider =
    Provider<WorktreeAgentTaskExecutionDelegate>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      final primaryDataSource = ref.watch(chatRemoteDataSourceProvider);
      final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
        router: ref.watch(meshEndpointRouterProvider),
        health: ref.watch(endpointHealthTrackerProvider),
        buildEndpointDataSource: (baseUrl, apiKey) => ChatRemoteDataSource(
          baseUrl: baseUrl,
          apiKey: apiKey,
          reasoningEffort: settings.reasoningEffort.apiValue,
        ),
      );
      final toolService = ref.watch(mcpToolServiceProvider);
      final verificationRunner = ref.watch(
        worktreeAgentVerificationRunnerProvider,
      );
      final delegate = WorktreeAgentLlmExecutionDelegate(
        settings: settings,
        primaryDataSource: primaryDataSource,
        meshRunner: meshRunner,
        toolService: toolService,
        verificationRunner: verificationRunner,
      );
      return delegate.execute;
    });

class WorktreeAgentLlmExecutionDelegate {
  const WorktreeAgentLlmExecutionDelegate({
    required this.settings,
    required this.primaryDataSource,
    required this.meshRunner,
    required this.toolService,
    required this.verificationRunner,
  });

  final AppSettings settings;
  final ChatDataSource primaryDataSource;
  final MeshSecondaryCompletionRunner<ChatDataSource> meshRunner;
  final McpToolService? toolService;
  final WorktreeAgentVerificationRunner verificationRunner;

  Future<WorktreeAgentTaskExecutionOutcome> execute(
    WorktreeAgentTaskExecutionContext context,
  ) async {
    final resolved = _resolveDataSource(context);
    final dispatcher = WorktreeAgentScopedToolDispatcher(
      toolService: toolService,
      worktreePath: context.worktreePath,
    );
    final service = SubagentExecutionService(dataSource: resolved.dataSource);
    final task = await service.run(
      id: _subagentTaskId(context.taskId),
      description: _description(context),
      prompt: _prompt(context, toolNames: dispatcher.toolNames),
      tools: dispatcher.toolDefinitions,
      dispatchToolCall: dispatcher.dispatch,
      model: resolved.model,
      temperature: LlmRequestTemperaturePolicy.forSettings(
        settings,
      ).agenticTemperature,
      maxTokens: settings.maxTokens,
      isBackground: true,
    );

    if (!resolved.isPrimary) {
      if (task.status == SubagentTaskStatus.failed) {
        meshRunner.health.recordFailure(resolved.endpointId);
      } else {
        meshRunner.health.recordSuccess(resolved.endpointId);
      }
    }

    if (task.status == SubagentTaskStatus.completed) {
      final summary = task.resultSummary.trim().isEmpty
          ? 'Worktree agent completed without a summary.'
          : task.resultSummary.trim();
      final verification = await verificationRunner.run(
        verificationCommand: context.verificationCommand,
        worktreePath: context.worktreePath,
      );
      return WorktreeAgentTaskExecutionOutcome(
        resultSummary: summary,
        verifiedGreen: verification.verifiedGreen,
        verificationSummary: verification.summary,
      );
    }

    final error = task.error?.trim();
    throw StateError(
      error == null || error.isEmpty ? 'Worktree agent failed.' : error,
    );
  }

  ResolvedDataSource<ChatDataSource> _resolveDataSource(
    WorktreeAgentTaskExecutionContext context,
  ) {
    final taskEndpointId = context.endpointId.trim();
    final endpointId = settings.llmProvider == LlmProvider.openAiCompatible
        ? (taskEndpointId.isEmpty
              ? settings.subagentEndpointId
              : taskEndpointId)
        : '';
    return meshRunner.resolve(
      primary: primaryDataSource,
      primaryBaseUrl: settings.baseUrl,
      primaryApiKey: settings.apiKey,
      endpoints: settings.namedEndpoints,
      endpointId: endpointId,
      model: settings.effectiveSubagentModel,
      fallbackModel: settings.effectiveModel,
    );
  }

  String _subagentTaskId(String taskId) => 'worktree_agent_$taskId';

  String _description(WorktreeAgentTaskExecutionContext context) {
    return context.title.trim().isEmpty
        ? 'Worktree agent task ${context.taskId}'
        : context.title.trim();
  }

  String _prompt(
    WorktreeAgentTaskExecutionContext context, {
    required Iterable<String> toolNames,
  }) {
    final tools = toolNames.isEmpty ? 'none' : toolNames.join(', ');
    return [
      'You are executing an isolated worktree-agent task.',
      'Task id: ${context.taskId}',
      'Title: ${context.title}',
      'Assigned git worktree: ${context.worktreePath}',
      'Assigned branch: ${context.branchName}',
      if (context.checkpointLineageId.trim().isNotEmpty)
        'Checkpoint lineage: ${context.checkpointLineageId}',
      if (context.endpointId.trim().isNotEmpty)
        'Assigned endpoint: ${context.endpointId}',
      if (context.verificationCommand.trim().isNotEmpty)
        'Verification command: ${context.verificationCommand}',
      'Available tools: $tools',
      'Only inspect or modify files inside the assigned git worktree.',
      'Use relative paths from the worktree root when possible.',
      'Do not ask the user questions. If you cannot proceed safely, return a '
          'concise blocker summary.',
      'When finished, summarize the files touched and any verification you ran. '
          'If verification was not run, say so explicitly.',
      '',
      'Task prompt:',
      context.prompt,
    ].join('\n');
  }
}

class WorktreeAgentScopedToolDispatcher {
  WorktreeAgentScopedToolDispatcher({
    required McpToolService? toolService,
    required String worktreePath,
  }) : _toolService = toolService,
       _worktreePath = _normalizeAbsolutePath(worktreePath);

  static const Set<String> _allowedToolNames = {
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
    'write_file',
    'edit_file',
    'delete_file',
  };

  static const Map<String, String> _pathArgumentByToolName = {
    'list_directory': 'path',
    'read_file': 'path',
    'inspect_file': 'path',
    'find_files': 'path',
    'search_files': 'path',
    'write_file': 'path',
    'edit_file': 'path',
    'delete_file': 'path',
  };

  static const Set<String> _rootDefaultToolNames = {
    'list_directory',
    'find_files',
    'search_files',
  };

  final McpToolService? _toolService;
  final String _worktreePath;

  List<String> get toolNames => toolDefinitions
      .map(_toolName)
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  List<Map<String, dynamic>> get toolDefinitions {
    final service = _toolService;
    if (service == null) {
      return const <Map<String, dynamic>>[];
    }
    return service
        .getOpenAiToolDefinitions()
        .where(
          (definition) => _allowedToolNames.contains(_toolName(definition)),
        )
        .toList(growable: false);
  }

  Future<McpToolResult> dispatch(ToolCallInfo toolCall) async {
    final service = _toolService;
    if (service == null) {
      return _blockedResult(
        toolCall.name,
        code: 'tool_service_unavailable',
        message: 'Worktree-agent tools are unavailable.',
      );
    }
    if (!_allowedToolNames.contains(toolCall.name)) {
      return _blockedResult(
        toolCall.name,
        code: 'tool_not_allowed',
        message: 'Tool ${toolCall.name} is not allowed for worktree agents.',
      );
    }

    final scopedArguments = Map<String, dynamic>.from(toolCall.arguments);
    final scopeFailure = _scopePathArgument(toolCall.name, scopedArguments);
    if (scopeFailure != null) {
      return scopeFailure;
    }
    return service.executeTool(name: toolCall.name, arguments: scopedArguments);
  }

  McpToolResult? _scopePathArgument(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final pathKey = _pathArgumentByToolName[toolName];
    if (pathKey == null) {
      return null;
    }

    final rawPath = (arguments[pathKey] as String?)?.trim() ?? '';
    if (rawPath.isEmpty && _rootDefaultToolNames.contains(toolName)) {
      arguments[pathKey] = _worktreePath;
      return null;
    }
    if (rawPath.isEmpty) {
      return null;
    }

    final scopedPath = _resolveAgainstWorktree(rawPath);
    if (!_isInsideWorktree(scopedPath)) {
      return _blockedResult(
        toolName,
        code: 'worktree_scope_violation',
        message: 'Path is outside the assigned worktree.',
      );
    }
    arguments[pathKey] = scopedPath;
    return null;
  }

  String _resolveAgainstWorktree(String path) {
    if (_isAbsolutePath(path)) {
      return _normalizeAbsolutePath(path);
    }
    return _normalizeAbsolutePath(
      '$_worktreePath${Platform.pathSeparator}$path',
    );
  }

  bool _isInsideWorktree(String path) {
    return path == _worktreePath ||
        path.startsWith('$_worktreePath${Platform.pathSeparator}');
  }

  McpToolResult _blockedResult(
    String toolName, {
    required String code,
    required String message,
  }) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': message,
        'worktree': _worktreePath,
      }),
      isSuccess: false,
      errorMessage: message,
    );
  }

  String _toolName(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is! Map<String, dynamic>) {
      return '';
    }
    return (function['name'] as String?)?.trim() ?? '';
  }

  static bool _isAbsolutePath(String path) {
    if (path.startsWith('/')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
  }

  static String _normalizeAbsolutePath(String path) {
    final rawPath = path.trim();
    final absolutePath = _isAbsolutePath(rawPath)
        ? rawPath
        : '${Directory.current.path}${Platform.pathSeparator}$rawPath';
    return Uri.file(absolutePath).normalizePath().toFilePath();
  }
}

final worktreeAgentTaskExecutorProvider = Provider<WorktreeAgentTaskExecutor>((
  ref,
) {
  return WorktreeAgentTaskExecutor(ref);
});

class WorktreeAgentTaskExecutor {
  const WorktreeAgentTaskExecutor(this._ref);

  final Ref _ref;

  Future<WorktreeAgentTaskExecutionResult> execute(String taskId) async {
    final normalizedTaskId = taskId.trim();
    final registry = _ref.read(worktreeAgentTaskRegistryNotifierProvider);
    final task = registry.byId(normalizedTaskId);
    if (task == null) {
      return WorktreeAgentTaskExecutionResult.failed(
        taskId: normalizedTaskId,
        errorMessage: 'Worktree-agent task was not found.',
      );
    }
    if (task.status != WorktreeAgentTaskStatus.running) {
      return WorktreeAgentTaskExecutionResult.failed(
        taskId: task.id,
        errorMessage: 'Only running worktree-agent tasks can be executed.',
      );
    }

    final notifier = _ref.read(
      worktreeAgentTaskRegistryNotifierProvider.notifier,
    );
    try {
      final outcome = await _ref
          .read(worktreeAgentTaskExecutionDelegateProvider)
          .call(WorktreeAgentTaskExecutionContext(task: task));
      await notifier.markCompleted(
        task.id,
        resultSummary: outcome.resultSummary,
        verifiedGreen: outcome.verifiedGreen,
        verificationSummary: outcome.verificationSummary,
      );
      return WorktreeAgentTaskExecutionResult.succeeded(
        taskId: task.id,
        resultSummary: outcome.resultSummary.trim(),
        verifiedGreen: outcome.verifiedGreen,
        verificationSummary: outcome.verificationSummary.trim(),
      );
    } catch (error) {
      final errorMessage = error.toString();
      await notifier.markFailed(task.id, errorMessage);
      return WorktreeAgentTaskExecutionResult.failed(
        taskId: task.id,
        errorMessage: errorMessage,
      );
    }
  }
}
