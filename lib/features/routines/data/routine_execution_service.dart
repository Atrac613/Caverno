import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/agents_md_loader.dart';
import '../../../core/services/google_chat_delivery_service.dart';
import '../../../core/services/macos_computer_use_audit_log.dart';
import '../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../core/types/assistant_mode.dart';
import '../../../core/types/workspace_mode.dart';
import '../../../core/utils/content_parser.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/data/datasources/chat_remote_datasource.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../../chat/data/datasources/mcp_tool_service.dart';
import '../../chat/data/datasources/session_logging_chat_datasource.dart';
import '../../chat/domain/entities/mcp_tool_entity.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/services/system_prompt_builder.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../settings/domain/entities/app_settings.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/entities/routine.dart';
import '../domain/services/routine_computer_use_action_allowlist.dart';
import '../domain/services/routine_schedule_service.dart';
import '../domain/services/routine_tool_policy.dart';
import 'routine_tool_runner.dart';

final routineExecutionServiceProvider = Provider<RoutineExecutionService>((
  ref,
) {
  final settings = ref.watch(settingsNotifierProvider);
  final rawDataSource = ref.watch(chatRemoteDataSourceProvider);
  final loggingEnabled = LlmSessionLogStore.isEnabled(
    settingsEnabled: settings.enableLlmSessionLogs,
  );
  final dataSource =
      !loggingEnabled ||
          settings.demoMode ||
          rawDataSource is! ChatRemoteDataSource
      ? rawDataSource
      : SessionLoggingChatDataSource(
          delegate: rawDataSource,
          logStore: ref.watch(llmSessionLogStoreProvider),
        );
  return RoutineExecutionService(
    dataSource: dataSource,
    googleChatDeliveryService: ref.watch(googleChatDeliveryServiceProvider),
    mcpToolService: ref.watch(mcpToolServiceProvider),
    settings: settings,
    agentsMdLoader: ref.watch(agentsMdLoaderProvider),
  );
});

typedef RoutineProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class RoutineExecutionService {
  RoutineExecutionService({
    required ChatDataSource dataSource,
    GoogleChatDeliveryService? googleChatDeliveryService,
    McpToolService? mcpToolService,
    required AppSettings settings,
    RoutineToolRunner? toolRunner,
    RoutineProcessRunner? processRunner,
    AgentsMdLoader? agentsMdLoader,
  }) : _dataSource = dataSource,
       _googleChatDeliveryService = googleChatDeliveryService,
       _mcpToolService = mcpToolService,
       _toolRunner = toolRunner ?? RoutineToolRunner(dataSource: dataSource),
       _processRunner = processRunner ?? _defaultProcessRunner,
       _settings = settings,
       _agentsMdLoader = agentsMdLoader;

  static const String googleChatPostToolName = 'routine_google_chat_post';
  static const String _googleChatSourceLabel = 'Google Chat';
  static const String _safariSourceLabel = 'Safari';
  static const String _googleChatScopedNotificationGuidance =
      'When the prompt limits the notification to newly discovered, changed, '
      'failed, or matching items, include only those matching items in the '
      'Google Chat text. Do not include previous items, unchanged items, or the '
      'full current result list as extra context unless the prompt explicitly '
      'asks for them. If the prompt says to post only the newly discovered IP '
      'list, the text argument must contain only the newly discovered IP '
      'addresses. Do not include total active hosts, previous IPs, unchanged '
      'IPs, subnet metadata, timestamps, or explanatory context in that '
      'Google Chat text.';

  static Map<String, dynamic> get _googleChatPostToolDefinition => {
    'type': 'function',
    RoutineToolPolicy.routineToolDefinitionKey: true,
    McpToolEntity.openAiSourceLabelKey: _googleChatSourceLabel,
    'function': {
      'name': googleChatPostToolName,
      'description':
          'Post a concise routine-created message to the configured Google '
          'Chat incoming webhook. When the routine prompt asks for a '
          'conditional Google Chat notification and the condition is true, '
          'call this tool before the final answer. Do not claim that Google '
          'Chat was posted unless this tool has been called successfully. '
          '$_googleChatScopedNotificationGuidance',
      'parameters': {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description':
                'Message text to post to Google Chat. '
                'For scoped notifications, include only the matching items.',
          },
        },
        'required': ['text'],
      },
    },
  };

  static Map<String, dynamic> get _openSafariUrlToolDefinition => {
    'type': 'function',
    RoutineToolPolicy.routineToolDefinitionKey: true,
    McpToolEntity.openAiSourceLabelKey: _safariSourceLabel,
    'function': {
      'name': RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
      'description':
          'Open an allowlisted HTTP or HTTPS URL in Safari for a routine. '
          'Use this before Computer Use observation and approved input/click '
          'actions when the routine needs Safari to show a specific page.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'HTTP or HTTPS URL to open in Safari.',
          },
          'reason': {
            'type': 'string',
            'description': 'Why this Safari page is needed.',
          },
        },
        'required': ['url'],
      },
    },
  };

  final ChatDataSource _dataSource;
  final GoogleChatDeliveryService? _googleChatDeliveryService;
  final McpToolService? _mcpToolService;
  final RoutineToolRunner _toolRunner;
  final RoutineProcessRunner _processRunner;
  final AppSettings _settings;
  final AgentsMdLoader? _agentsMdLoader;
  final Uuid _uuid = const Uuid();
  static const int _maxStoredOutputLength = 24000;
  static const int _maxStoredToolArgumentsLength = 4000;
  static const int _maxStoredToolResultLength = 12000;
  static const int _maxGeneratedPlanLength = 12000;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    final startedAt = DateTime.now();
    final runId = _uuid.v4();

    return LlmSessionLogContext.run(
      _routineLogContext(routine, runId: runId, phase: 'routine_run'),
      () async {
        try {
          final allowedTools = _allowedRoutineTools(routine);
          final approvedPlan = routine.freshApprovedPlanMarkdown;
          final systemPrompt = _buildRoutineSystemPrompt(
            now: startedAt,
            routine: routine,
            allowedTools: allowedTools,
            approvedPlan: approvedPlan,
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
              id: runId,
              startedAt: startedAt,
              finishedAt: finishedAt,
              status: RoutineRunStatus.failed,
              trigger: trigger,
              usedPlan: approvedPlan != null,
              planSourceHash: approvedPlan == null
                  ? ''
                  : routine.planSourceHash,
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
            id: runId,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: RoutineRunStatus.completed,
            trigger: trigger,
            usedPlan: approvedPlan != null,
            planSourceHash: approvedPlan == null ? '' : routine.planSourceHash,
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
            id: runId,
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: RoutineRunStatus.failed,
            trigger: trigger,
            durationMs: durationMs,
            preview: message,
            error: message,
          );
        }
      },
    );
  }

  Future<String> generatePlanDraft(Routine routine) async {
    return LlmSessionLogContext.run(
      _routineLogContext(routine, phase: 'routine_plan'),
      () async {
        final now = DateTime.now();
        final allowedTools = _allowedRoutineTools(routine);
        final toolNames = _toolNamesFromDefinitions(allowedTools);
        final messages = [
          Message(
            id: 'routine_plan_system',
            content: _buildRoutinePlanSystemPrompt(
              now: now,
              routine: routine,
              allowedToolNames: toolNames,
            ),
            role: MessageRole.system,
            timestamp: now,
          ),
          Message(
            id: 'routine_plan_user',
            content: _buildRoutinePlanDraftRequest(
              routine: routine,
              allowedToolNames: toolNames,
            ),
            role: MessageRole.user,
            timestamp: now,
          ),
        ];

        final result = await _dataSource.createChatCompletion(
          messages: messages,
          model: _settings.model,
          temperature: _settings.temperature,
          maxTokens: _settings.maxTokens,
        );
        final markdown = _textSegmentsOnly(result.content).trimRight();
        if (markdown.trim().isEmpty) {
          throw StateError(
            'Routine plan draft generation returned no content.',
          );
        }
        return RoutineScheduleService.truncateOutput(
          markdown,
          maxLength: _maxGeneratedPlanLength,
        );
      },
    );
  }

  LlmSessionLogContext _routineLogContext(
    Routine routine, {
    String? runId,
    required String phase,
  }) {
    final sessionId = runId == null
        ? 'routine-plan-${routine.id}'
        : 'routine-${routine.id}-run-$runId';
    return LlmSessionLogContext(
      workspaceMode: WorkspaceMode.routines,
      sessionId: sessionId,
      sessionTitle: routine.trimmedName,
      routineId: routine.id,
      routineRunId: runId,
      phase: phase,
    );
  }

  String _resolveLanguageCode() {
    final preference = _settings.language.trim().toLowerCase();
    if (preference == 'ja' || preference == 'en') {
      return preference;
    }
    return 'en';
  }

  String _buildRoutinePlanSystemPrompt({
    required DateTime now,
    required Routine routine,
    required List<String> allowedToolNames,
  }) {
    final basePrompt = SystemPromptBuilder.build(
      now: now,
      assistantMode: AssistantMode.general,
      languageCode: _resolveLanguageCode(),
      toolNames: allowedToolNames,
    );

    final agentsMdBlock = _routineAgentsMdBlock(routine);

    return [
      basePrompt,
      ?agentsMdBlock,
      'Routine plan mode: create a reviewable Markdown execution plan for an '
          'unattended routine. Do not execute the routine. Do not call tools. '
          'Do not ask follow-up questions. If information is missing, write '
          'explicit assumptions and safe fallback steps. Keep the plan concise '
          'enough to be injected into future routine executions.',
    ].join('\n');
  }

  String _buildRoutinePlanDraftRequest({
    required Routine routine,
    required List<String> allowedToolNames,
  }) {
    final buffer = StringBuffer()
      ..writeln('Create a routine execution plan for this routine.')
      ..writeln()
      ..writeln('Routine name:')
      ..writeln(routine.trimmedName)
      ..writeln()
      ..writeln('Routine prompt:')
      ..writeln(routine.trimmedPrompt)
      ..writeln()
      ..writeln('Schedule:')
      ..writeln(_routineScheduleDescription(routine))
      ..writeln()
      ..writeln('Tools:')
      ..writeln(
        allowedToolNames.isEmpty
            ? 'No routine tools are enabled.'
            : allowedToolNames.join(', '),
      )
      ..writeln()
      ..writeln('Workspace:')
      ..writeln(
        routine.hasWorkspaceDirectory
            ? routine.trimmedWorkspaceDirectory
            : 'No routine workspace directory is configured.',
      )
      ..writeln()
      ..writeln('Workspace writes:')
      ..writeln(routine.hasWorkspaceWriteAccess ? 'Allowed' : 'Not allowed')
      ..writeln()
      ..writeln('Completion action:')
      ..writeln(routine.completionAction.name);

    final currentPlan =
        routine.effectivePlanArtifact.normalizedDraftMarkdown ??
        routine.effectivePlanArtifact.normalizedApprovedMarkdown;
    if (currentPlan != null) {
      buffer
        ..writeln()
        ..writeln('Existing plan to revise:')
        ..writeln(_truncateApprovedPlanForPrompt(currentPlan));
    }

    buffer
      ..writeln()
      ..writeln('Return only Markdown with these sections:')
      ..writeln('- Objective')
      ..writeln('- Approved Scope')
      ..writeln('- Execution Steps')
      ..writeln('- Tool and Workspace Policy')
      ..writeln('- Completion Criteria')
      ..writeln('- Failure Handling');

    return buffer.toString().trimRight();
  }

  String _routineScheduleDescription(Routine routine) {
    if (routine.scheduleMode == RoutineScheduleMode.dailyTime) {
      return 'Daily at ${RoutineScheduleService.formatTimeOfDayMinutes(routine.timeOfDayMinutes)}';
    }
    return 'Every ${RoutineScheduleService.normalizeIntervalValue(routine.intervalValue)} '
        '${routine.intervalUnit.name}';
  }

  String _buildRoutineSystemPrompt({
    required DateTime now,
    required Routine routine,
    required List<Map<String, dynamic>> allowedTools,
    String? approvedPlan,
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

    final agentsMdBlock = _routineAgentsMdBlock(routine);

    if (allowedTools.isEmpty &&
        routineGuidance.isEmpty &&
        approvedPlan == null &&
        agentsMdBlock == null) {
      return basePrompt;
    }

    return [
      basePrompt,
      ?agentsMdBlock,
      if (approvedPlan != null) ...[
        'Approved routine plan: the user approved this plan for the current '
            'routine configuration. Follow it during unattended execution. '
            'Treat the current routine prompt as the live trigger and the '
            'approved plan as the execution contract. Do not expand the scope '
            'beyond the approved plan unless a safe read-only check is needed '
            'to complete the routine.',
        _truncateApprovedPlanForPrompt(approvedPlan),
      ],
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

  String _truncateApprovedPlanForPrompt(String plan) {
    return RoutineScheduleService.truncateOutput(plan, maxLength: 6000);
  }

  String? _routineAgentsMdBlock(Routine routine) {
    if (!_settings.enableAgentsMd) return null;
    final loader = _agentsMdLoader;
    if (loader == null) return null;
    if (!routine.hasWorkspaceDirectory) return null;
    final content = loader.loadForProject(routine.trimmedWorkspaceDirectory);
    final trimmed = content?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return [
      'The following AGENTS.md from the routine workspace directory '
          'contains project-specific guidance the user maintains for coding '
          'agents. Treat it as authoritative for this routine unless it '
          'conflicts with the routine prompt or the safety and oversight '
          'rules above.',
      '<agents_md>',
      trimmed,
      '</agents_md>',
    ].join('\n');
  }

  String _textSegmentsOnly(String content) {
    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    return buffer.toString();
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
        'for a Google Chat notification is satisfied. If that condition is '
        'satisfied, call $googleChatPostToolName before the final answer. Do '
        'not say that Google Chat was posted unless the tool has been called '
        'successfully. Keep the message concise. '
        '$_googleChatScopedNotificationGuidance',
      );
    }
    final allowedComputerUseActionToolNames =
        RoutineComputerUseActionAllowlist.allowedToolNames(
          _settings.enabledRoutineComputerUseActionAllowlist,
        );
    if (allowedToolNames.any(
      RoutineToolPolicy.isComputerUseObservationToolName,
    )) {
      guidance.add(
        allowedComputerUseActionToolNames.isEmpty
            ? 'Computer Use is available only for observation during routines. '
                  'You may inspect permissions, windows, displays, screenshots, '
                  'or visual state, but routines cannot perform unattended '
                  'pointer, keyboard, focus, audio, posting, sending, '
                  'submitting, or publishing actions.'
            : 'Computer Use observation tools are available during routines. '
                  'Action tools are limited by the routine allowlist below; do '
                  'not call any Computer Use action that is not allowlisted.',
      );
    }
    if (allowedComputerUseActionToolNames.isNotEmpty) {
      guidance.add(
        'Computer Use action auto-execution is restricted by the routine '
        'allowlist. Only these action tools may run automatically when the '
        'tool arguments also match an enabled allowlist entry: '
        '${allowedComputerUseActionToolNames.join(', ')}. Include concrete '
        'target metadata such as target.label, target.role, target.action, '
        'target.risk, target.appName, target.appBundleId, and '
        'target.windowTitle. For text input, include the exact text in text. '
        'Public posting, sending, submitting, or publishing controls must use '
        'target.risk=public_action.',
      );
      if (allowedComputerUseActionToolNames.contains(
        RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
      )) {
        guidance.add(
          'When a routine needs Safari, call '
          '${RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName} '
          'with the exact allowlisted URL first, then observe the page before '
          'typing or clicking. For public posting flows, type only the exact '
          'allowlisted text, observe the result, and click only the '
          'allowlisted public-action target.',
        );
      }
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
    final allowedComputerUseActionToolNames =
        RoutineComputerUseActionAllowlist.allowedToolNames(
          _settings.enabledRoutineComputerUseActionAllowlist,
        );
    return RoutineToolPolicy.filterAllowedToolDefinitions(
      _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
      allowWorkspaceWrites: routine.hasWorkspaceWriteAccess,
      allowedComputerUseActionToolNames: allowedComputerUseActionToolNames,
      extraDefinitions: [
        ...extraDefinitions,
        if (allowedComputerUseActionToolNames.contains(
          RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName,
        ))
          _openSafariUrlToolDefinition,
      ],
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
      if (RoutineToolPolicy.isComputerUseActionToolName(toolCall.name)) {
        return RoutineToolPolicy.buildComputerUseActionDeniedResult(toolCall);
      }
      return RoutineToolPolicy.buildDeniedResult(toolCall);
    }

    if (toolCall.name == googleChatPostToolName) {
      return _postRoutineGoogleChatMessage(toolCall);
    }

    final computerUseAllowlistEntry =
        RoutineComputerUseActionAllowlist.matchingEntry(
          toolCall: toolCall,
          entries: _settings.enabledRoutineComputerUseActionAllowlist,
        );
    if (RoutineToolPolicy.isComputerUseActionToolName(toolCall.name) &&
        computerUseAllowlistEntry == null) {
      return RoutineToolPolicy.buildComputerUseActionDeniedResult(toolCall);
    }
    if (toolCall.name ==
        RoutineComputerUseActionAllowlist.routineOpenSafariUrlToolName) {
      if (computerUseAllowlistEntry == null) {
        return RoutineToolPolicy.buildComputerUseActionDeniedResult(toolCall);
      }
      final result = await _openRoutineSafariUrl(toolCall);
      _recordRoutineComputerUseAllowlistResult(
        toolCall: toolCall,
        allowlistEntry: computerUseAllowlistEntry,
        result: result,
      );
      return result;
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

    final result = await toolService.executeTool(
      name: toolCall.name,
      arguments: scopedArgumentsResult.arguments,
    );
    if (computerUseAllowlistEntry != null) {
      _recordRoutineComputerUseAllowlistResult(
        toolCall: toolCall,
        allowlistEntry: computerUseAllowlistEntry,
        result: result,
      );
    }
    return result;
  }

  Future<McpToolResult> _openRoutineSafariUrl(ToolCallInfo toolCall) async {
    if (!Platform.isMacOS) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'unsupported_platform',
          'error': 'Opening Safari URLs is only available on macOS.',
        }),
        isSuccess: false,
        errorMessage: 'Opening Safari URLs is only available on macOS',
      );
    }

    final url = (toolCall.arguments['url'] as String?)?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({
          'ok': false,
          'code': 'invalid_url',
          'error': 'routine_open_safari_url requires an HTTP or HTTPS URL.',
          'url': url,
        }),
        isSuccess: false,
        errorMessage: 'Invalid Safari URL',
      );
    }

    final processResult = await _processRunner('/usr/bin/open', [
      '-a',
      'Safari',
      url,
    ]);
    final success = processResult.exitCode == 0;
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': success,
        'schemaName': 'routine_safari_url_open_result',
        'url': url,
        'appName': 'Safari',
        'exitCode': processResult.exitCode,
        if ((processResult.stdout as String).trim().isNotEmpty)
          'stdout': (processResult.stdout as String).trim(),
        if ((processResult.stderr as String).trim().isNotEmpty)
          'stderr': (processResult.stderr as String).trim(),
        'nextAction': success
            ? 'Run computer_vision_observe to verify Safari and the page before input or click actions.'
            : 'Check Safari availability and the URL allowlist before retrying.',
      }),
      isSuccess: success,
      errorMessage: success
          ? null
          : ((processResult.stderr as String).trim().isEmpty
                ? 'Failed to open Safari URL'
                : (processResult.stderr as String).trim()),
    );
  }

  void _recordRoutineComputerUseAllowlistResult({
    required ToolCallInfo toolCall,
    required RoutineComputerUseActionAllowlistEntry allowlistEntry,
    required McpToolResult result,
  }) {
    MacosComputerUseAuditLog.instance.record(
      toolName: toolCall.name,
      policy: MacosComputerUseToolPolicy.decision(toolCall.name),
      approvalResult: 'routine_allowlist:${allowlistEntry.id}',
      success: result.isSuccess,
      result: result.result,
      errorCode: result.errorMessage,
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
