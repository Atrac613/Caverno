import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_coordinator.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_guardrails.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

import 'plan_mode_execution_progress.dart';
import 'plan_mode_heartbeat.dart';

class PlanModeHarnessExecutionHandle {
  PlanModeHarnessExecutionHandle(
    this.done, {
    PlanModeHarnessCancellationSignal? cancellationSignal,
  }) : _cancellationSignal =
           cancellationSignal ?? PlanModeHarnessCancellationSignal();

  final Future<void> done;
  final PlanModeHarnessCancellationSignal _cancellationSignal;

  bool get cleanupCancellationRequested =>
      _cancellationSignal.isCancellationRequested;

  void requestCleanupCancellation() {
    _cancellationSignal.requestCancellation();
  }
}

class PlanModeHarnessCancellationSignal {
  bool _isCancellationRequested = false;

  bool get isCancellationRequested => _isCancellationRequested;

  void requestCancellation() {
    _isCancellationRequested = true;
  }
}

Future<PlanModeHarnessExecutionHandle>
approvePlanAndStartPlanModeHarnessExecution(
  ProviderContainer container, {
  required Directory scenarioDir,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
  required PlanModeTimeoutBudgets budgets,
  int? taskExecutionLimit,
  String languageCode = 'en',
}) async {
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  final chatNotifier = container.read(chatNotifierProvider.notifier);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (conversation == null) {
    throw StateError('Cannot approve plan because no conversation is active.');
  }

  final currentArtifact = conversation.effectivePlanArtifact;
  final draftMarkdown =
      currentArtifact.normalizedDraftMarkdown ??
      currentArtifact.normalizedApprovedMarkdown;
  if (draftMarkdown == null) {
    throw StateError('Cannot approve plan because no plan document exists.');
  }

  final validation = ConversationPlanProjectionService.validateDocument(
    markdown: draftMarkdown,
    requireTasks: true,
  );
  if (!validation.isValid || validation.projection == null) {
    throw StateError(
      'Cannot approve plan because the plan document is invalid: '
      '${validation.errorMessage ?? 'unknown validation error'}.',
    );
  }

  final approvedWorkflowStage = switch (validation.workflowStage) {
    ConversationWorkflowStage.tasks ||
    ConversationWorkflowStage.implement ||
    ConversationWorkflowStage.review => validation.workflowStage!,
    _ =>
      validation.previewTasks.isEmpty
          ? ConversationWorkflowStage.tasks
          : ConversationWorkflowStage.implement,
  };
  final approvedMarkdown =
      ConversationPlanProjectionService.replaceWorkflowStage(
        markdown: draftMarkdown,
        workflowStage: approvedWorkflowStage,
      );
  final updatedAt = DateTime.now();
  final nextArtifact = currentArtifact
      .copyWith(
        draftMarkdown: approvedMarkdown,
        approvedMarkdown: approvedMarkdown,
        updatedAt: updatedAt,
      )
      .recordRevision(
        markdown: approvedMarkdown,
        kind: ConversationPlanRevisionKind.approved,
        label: 'Approved plan from live test harness',
        createdAt: updatedAt,
      );

  await conversationsNotifier.updateCurrentPlanArtifact(
    planArtifact: nextArtifact,
    clearPlanArtifact: !nextArtifact.hasContent,
  );
  final refreshed = await conversationsNotifier
      .refreshCurrentWorkflowProjectionFromApprovedPlan();
  if (!refreshed && validation.workflowSpec != null) {
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: approvedWorkflowStage,
      workflowSpec: validation.workflowSpec!,
    );
  }
  await conversationsNotifier.exitPlanningSession();
  chatNotifier.dismissPlanProposal();

  final executionConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  if (executionConversation == null) {
    throw StateError('Cannot start execution because no saved task is ready.');
  }
  final nextTask = ConversationPlanExecutionCoordinator.nextTask(
    executionConversation,
  );
  if (nextTask == null) {
    throw StateError('Cannot start execution because no saved task is ready.');
  }

  phaseTrace.approvalTappedAt = DateTime.now();
  heartbeatWriter.write(
    phase: 'execution',
    subphase: 'approvedViaHarness',
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: nextTask.title,
    workflowSnapshot: summarizePlanModeWorkflowTasks(
      executionConversation.projectedExecutionTasks,
    ),
    messageCount: executionConversation.messages.length,
    hasPendingApprovals: false,
    isLoading: true,
  );

  await conversationsNotifier.updateCurrentExecutionTaskProgress(
    taskId: nextTask.id,
    status: ConversationWorkflowTaskStatus.inProgress,
    lastRunAt: DateTime.now(),
    summary: 'Started from the live test harness approval fallback.',
    eventType: ConversationExecutionTaskEventType.started,
  );

  final startedConversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final previousAssistantMessageId = latestPlanModeHarnessAssistantMessageId(
    startedConversation,
  );
  phaseTrace.firstTaskStartedAt ??= DateTime.now();
  phaseTrace.firstTaskTitle ??= nextTask.title;
  heartbeatWriter.write(
    phase: 'execution',
    subphase: 'startedViaHarness',
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: nextTask.title,
    workflowSnapshot: summarizePlanModeWorkflowTasks(
      startedConversation?.projectedExecutionTasks ??
          executionConversation.projectedExecutionTasks,
    ),
    messageCount: startedConversation?.messages.length ?? 0,
    hasPendingApprovals: false,
    isLoading: true,
  );

  final cancellationSignal = PlanModeHarnessCancellationSignal();
  return PlanModeHarnessExecutionHandle(
    _runApprovedTaskFromHarness(
      container,
      scenarioDir: scenarioDir,
      task: nextTask,
      previousAssistantMessageId: previousAssistantMessageId,
      cancellationSignal: cancellationSignal,
      taskExecutionLimit: taskExecutionLimit,
      languageCode: languageCode,
    ),
    cancellationSignal: cancellationSignal,
  );
}

Future<void> _runApprovedTaskFromHarness(
  ProviderContainer container, {
  required Directory scenarioDir,
  required ConversationWorkflowTask task,
  required String? previousAssistantMessageId,
  required PlanModeHarnessCancellationSignal cancellationSignal,
  required int? taskExecutionLimit,
  required String languageCode,
}) async {
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  var currentTask = task;
  var currentPreviousAssistantMessageId = previousAssistantMessageId;
  var currentPrompt = ConversationPlanExecutionCoordinator.buildTaskPrompt(
    task: currentTask,
    intro: 'Use the approved saved task now: ${currentTask.title}',
    targetFilesLabel: 'Target files',
    validationLabel: 'Validation',
    notesLabel: 'Notes',
    outro:
        'Implement this task now. Use available tools and report completion evidence.',
  );
  var useHiddenPrompt = false;
  var recoveryAttemptsForCurrentTask = 0;
  var completedTaskCount = 0;
  try {
    for (var depth = 0; depth < 8; depth += 1) {
      if (cancellationSignal.isCancellationRequested) {
        return;
      }
      final producedEvidence = await _runHarnessTaskTurn(
        container,
        scenarioDir: scenarioDir,
        task: currentTask,
        previousAssistantMessageId: currentPreviousAssistantMessageId,
        prompt: currentPrompt,
        useHiddenPrompt: useHiddenPrompt,
        cancellationSignal: cancellationSignal,
        languageCode: languageCode,
      );
      if (cancellationSignal.isCancellationRequested) {
        return;
      }
      if (!producedEvidence) {
        return;
      }

      final conversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      if (conversation == null) {
        return;
      }
      final completedTask = conversation.projectedExecutionTasks.firstWhere(
        (candidate) => candidate.id == currentTask.id,
        orElse: () => currentTask,
      );
      if (completedTask.status != ConversationWorkflowTaskStatus.completed) {
        if (completedTask.status == ConversationWorkflowTaskStatus.inProgress &&
            recoveryAttemptsForCurrentTask < 2) {
          final latestConversation = container
              .read(conversationsNotifierProvider)
              .currentConversation;
          currentPreviousAssistantMessageId =
              latestPlanModeHarnessAssistantMessageId(latestConversation);
          currentTask = completedTask;
          currentPrompt =
              ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
                task: completedTask,
              );
          useHiddenPrompt = true;
          recoveryAttemptsForCurrentTask += 1;
          appLog(
            '[Workflow] Harness requested tool-less recovery for saved task: ${completedTask.title}',
          );
          continue;
        }
        if (completedTask.status == ConversationWorkflowTaskStatus.inProgress) {
          const blockedReason =
              'No concrete tool evidence was produced after bounded tool-less recovery.';
          await conversationsNotifier.updateCurrentExecutionTaskProgress(
            taskId: completedTask.id,
            status: ConversationWorkflowTaskStatus.blocked,
            allowStatusRegression: true,
            blockedReason: blockedReason,
            summary: blockedReason,
            eventType: ConversationExecutionTaskEventType.blocked,
            eventSummary: blockedReason,
          );
          appLog(
            '[Workflow] Harness blocked saved task after tool-less recovery: ${completedTask.title}',
          );
        }
        return;
      }
      completedTaskCount += 1;

      final missingTargetFiles = missingPlanModeHarnessTargetFiles(
        scenarioDir,
        completedTask,
      );
      if (missingTargetFiles.isNotEmpty) {
        final missingSummary =
            'Saved target files are still missing: ${missingTargetFiles.join(', ')}.';
        if (recoveryAttemptsForCurrentTask < 3) {
          await conversationsNotifier.updateCurrentExecutionTaskProgress(
            taskId: completedTask.id,
            status: ConversationWorkflowTaskStatus.inProgress,
            allowStatusRegression: true,
            lastRunAt: DateTime.now(),
            summary: missingSummary,
            eventSummary: missingSummary,
          );
          final latestConversation = container
              .read(conversationsNotifierProvider)
              .currentConversation;
          currentPreviousAssistantMessageId =
              latestPlanModeHarnessAssistantMessageId(latestConversation);
          currentTask =
              latestConversation?.projectedExecutionTasks.firstWhere(
                (candidate) => candidate.id == completedTask.id,
                orElse: () => completedTask,
              ) ??
              completedTask;
          currentPrompt =
              ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
                task: currentTask,
                missingTargetFiles: missingTargetFiles,
                failedCommand: currentTask.validationCommand.trim().isNotEmpty
                    ? currentTask.validationCommand
                    : 'target file existence audit',
              );
          useHiddenPrompt = true;
          recoveryAttemptsForCurrentTask += 1;
          appLog(
            '[Workflow] Harness kept saved task active because target files are missing: ${missingTargetFiles.join(', ')}',
          );
          continue;
        }

        await conversationsNotifier.updateCurrentExecutionTaskProgress(
          taskId: completedTask.id,
          status: ConversationWorkflowTaskStatus.blocked,
          allowStatusRegression: true,
          blockedReason: missingSummary,
          summary:
              'Harness blocked the saved task after missing target recovery.',
          eventType: ConversationExecutionTaskEventType.blocked,
          eventSummary: missingSummary,
        );
        appLog(
          '[Workflow] Harness blocked saved task after missing target recovery: ${completedTask.title}',
        );
        return;
      }

      if (taskExecutionLimit != null &&
          completedTaskCount >= taskExecutionLimit) {
        appLog(
          '[Workflow] Harness stopped after reaching task execution limit: $taskExecutionLimit',
        );
        return;
      }

      final nextTask = ConversationPlanExecutionCoordinator.nextTask(
        conversation,
      );
      if (nextTask == null || nextTask.id == completedTask.id) {
        return;
      }

      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: nextTask.id,
        status: ConversationWorkflowTaskStatus.inProgress,
        lastRunAt: DateTime.now(),
        summary:
            'Auto-continued to the next saved task after completing "${completedTask.title}".',
        eventType: ConversationExecutionTaskEventType.started,
      );
      appLog(
        '[Workflow] Harness auto-continued to next saved task: ${nextTask.title}',
      );

      if (cancellationSignal.isCancellationRequested) {
        return;
      }
      final startedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      currentPreviousAssistantMessageId =
          latestPlanModeHarnessAssistantMessageId(startedConversation);
      currentTask = nextTask;
      currentPrompt =
          ConversationPlanExecutionCoordinator.buildAutoContinueTaskPrompt(
            completedTask: completedTask,
            nextTask: nextTask,
          );
      useHiddenPrompt = true;
      recoveryAttemptsForCurrentTask = 0;
    }
  } catch (error, stackTrace) {
    if (cancellationSignal.isCancellationRequested &&
        isPlanModeHarnessProviderContainerDisposedError(error)) {
      appLog(
        '[Workflow] Harness background execution stopped after cleanup cancellation.',
      );
      return;
    }
    appLog('[Workflow] Harness task execution failed: $error');
    appLog('$stackTrace');
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: currentTask.id,
      status: ConversationWorkflowTaskStatus.blocked,
      blockedReason: error.toString(),
      summary: 'Harness task execution failed before completion.',
      eventType: ConversationExecutionTaskEventType.blocked,
      eventSummary: error.toString(),
    );
  }
}

Future<bool> _runHarnessTaskTurn(
  ProviderContainer container, {
  required Directory scenarioDir,
  required ConversationWorkflowTask task,
  required String? previousAssistantMessageId,
  required String prompt,
  required bool useHiddenPrompt,
  required PlanModeHarnessCancellationSignal cancellationSignal,
  required String languageCode,
}) async {
  if (cancellationSignal.isCancellationRequested) {
    return false;
  }
  final chatNotifier = container.read(chatNotifierProvider.notifier);
  final conversationsNotifier = container.read(
    conversationsNotifierProvider.notifier,
  );
  await _sendHarnessPromptWithApprovals(
    container,
    scenarioDir: scenarioDir,
    task: task,
    cancellationSignal: cancellationSignal,
    send: () {
      if (useHiddenPrompt) {
        return chatNotifier.sendHiddenPrompt(
          prompt,
          languageCode: languageCode,
        );
      }
      return chatNotifier.sendMessage(
        prompt,
        languageCode: languageCode,
        bypassPlanMode: true,
      );
    },
  );
  if (cancellationSignal.isCancellationRequested) {
    return false;
  }

  final toolResults = chatNotifier.takeLatestToolResults();
  final hiddenAssistantResponse = chatNotifier
      .takeLatestHiddenAssistantResponse();
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final latestAssistantResponse = latestPlanModeHarnessAssistantResponseAfter(
    conversation,
    previousAssistantMessageId,
  );
  final primaryAssistantResponse =
      useHiddenPrompt && (hiddenAssistantResponse?.trim().isNotEmpty ?? false)
      ? hiddenAssistantResponse!.trim()
      : latestAssistantResponse;
  final fallbackResponse = buildPlanModeHarnessFallbackAssistantResponse(
    toolResults: toolResults,
    hiddenAssistantResponse: useHiddenPrompt ? null : hiddenAssistantResponse,
  );
  if (primaryAssistantResponse.trim().isEmpty &&
      fallbackResponse.trim().isEmpty) {
    return false;
  }

  final completionAssessment = assessPlanModeHarnessTaskCompletion(
    task: task,
    toolResults: toolResults,
  );
  appLog(
    '[Workflow] Harness completion evidence: '
    'task=${task.title}, '
    'tools=${toolResults.map((result) => result.name).join(',')}, '
    'successfulValidationCommands='
    '${completionAssessment.successfulValidationCommands.length}, '
    'failedValidationCommands='
    '${completionAssessment.failedValidationCommands.length}, '
    'results=${toolResults.map(_summarizeHarnessToolResult).join(' | ')}, '
    'hasFailure=${completionAssessment.hasFailure}, '
    'shouldMarkCompleted=${completionAssessment.shouldMarkCompleted}',
  );
  if (completionAssessment.shouldMarkCompleted) {
    final successfulValidation =
        completionAssessment.successfulValidationCommands.isEmpty
        ? null
        : completionAssessment.successfulValidationCommands.first;
    final summary = successfulValidation == null
        ? 'Harness confirmed saved task completion from target file mutations.'
        : 'Harness confirmed saved task completion with $successfulValidation.';
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: summary,
      validationStatus: successfulValidation == null
          ? null
          : ConversationExecutionValidationStatus.passed,
      lastValidationAt: successfulValidation == null ? null : DateTime.now(),
      lastValidationCommand: successfulValidation,
      lastValidationSummary: successfulValidation == null ? null : summary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: summary,
    );
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: ConversationWorkflowStage.review,
      preserveWorkflowProjection: true,
    );
  } else {
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.inProgress,
      allowStatusRegression: true,
      summary:
          'Harness retained the saved task because this turn did not produce matching completion evidence.',
      eventSummary:
          'Assistant completion narration was not accepted without matching tool evidence.',
    );
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
    );
  }
  return true;
}

String _summarizeHarnessToolResult(ToolResultInfo result) {
  final normalized = result.result.replaceAll(RegExp(r'\s+'), ' ').trim();
  final summary = normalized.length <= 180
      ? normalized
      : '${normalized.substring(0, 180)}...';
  return '${result.name}:$summary';
}

ConversationPlanExecutionCompletionAssessment
assessPlanModeHarnessTaskCompletion({
  required ConversationWorkflowTask task,
  required List<ToolResultInfo> toolResults,
}) {
  return ConversationPlanExecutionGuardrails.assessTaskCompletion(
    task: task,
    toolResults: toolResults,
  );
}

Future<void> _sendHarnessPromptWithApprovals(
  ProviderContainer container, {
  required Directory scenarioDir,
  required ConversationWorkflowTask task,
  required Future<void> Function() send,
  required PlanModeHarnessCancellationSignal cancellationSignal,
}) async {
  final chatNotifier = container.read(chatNotifierProvider.notifier);
  final completion = Completer<void>();
  unawaited(
    send()
        .then((_) {
          if (!completion.isCompleted) {
            completion.complete();
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) {
            completion.completeError(error, stackTrace);
          }
        }),
  );

  while (!completion.isCompleted) {
    final pendingFileOperation = container
        .read(chatNotifierProvider)
        .pendingFileOperation;
    if (pendingFileOperation != null) {
      final approved =
          !cancellationSignal.isCancellationRequested &&
          _isSafeHarnessFileOperation(pendingFileOperation, scenarioDir);
      chatNotifier.resolveFileOperation(
        id: pendingFileOperation.id,
        approved: approved,
      );
      appLog(
        approved
            ? '[Workflow] Harness approved file operation: '
                  '${pendingFileOperation.operation} ${pendingFileOperation.path}'
            : '[Workflow] Harness denied file operation: '
                  '${pendingFileOperation.operation} ${pendingFileOperation.path}',
      );
    }
    final pendingLocalCommand = container
        .read(chatNotifierProvider)
        .pendingLocalCommand;
    if (pendingLocalCommand != null) {
      final approved =
          !cancellationSignal.isCancellationRequested &&
          isSafePlanModeHarnessLocalCommand(
            pending: pendingLocalCommand,
            scenarioDir: scenarioDir,
            task: task,
          );
      chatNotifier.resolveLocalCommand(
        id: pendingLocalCommand.id,
        approval: LocalCommandApproval(approved: approved),
      );
      appLog(
        approved
            ? '[Workflow] Harness approved local command: '
                  '${pendingLocalCommand.command}'
            : '[Workflow] Harness denied local command: '
                  '${pendingLocalCommand.command}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  await completion.future;
}

bool _isSafeHarnessFileOperation(
  PendingFileOperation pending,
  Directory scenarioDir,
) {
  final path = pending.path.trim();
  if (path.isEmpty) {
    return false;
  }
  if (path.startsWith(Platform.pathSeparator)) {
    return _isWithinScenarioWorkspace(path, scenarioDir);
  }
  final segments = path.split(RegExp(r'[/\\]+'));
  return !segments.contains('..');
}

bool isSafePlanModeHarnessLocalCommand({
  required PendingLocalCommand pending,
  required Directory scenarioDir,
  required ConversationWorkflowTask task,
}) {
  final command = pending.command.trimLeft();
  var args = GitTools.splitArgs(command);
  if (args.isEmpty) {
    return false;
  }
  final workingDirectory = pending.workingDirectory.trim();
  final usesScenarioWorkspace =
      command.contains(scenarioDir.path) ||
      workingDirectory.isEmpty ||
      _isWithinScenarioWorkspace(workingDirectory, scenarioDir);
  if (!usesScenarioWorkspace) {
    return false;
  }
  if (args.length >= 4 && args[0] == 'cd' && args[2] == '&&') {
    if (!_isExactHarnessScenarioRoot(args[1], scenarioDir)) {
      return false;
    }
    args = args.sublist(3);
  }
  if (_matchesHarnessSavedValidationCommand(args, task.validationCommand)) {
    return _isSafeHarnessSavedValidationCommand(args, scenarioDir, task);
  }
  if (args.any(_isHarnessShellControlArgument)) {
    return false;
  }
  return _isSafeHarnessDartRuntimeInfoCommand(args) ||
      _isSafeHarnessDartScaffoldCommand(args, scenarioDir, task) ||
      _isSafeHarnessDartProjectCommand(args, scenarioDir) ||
      _isSafeHarnessDirectoryCreationCommand(args, scenarioDir) ||
      _isSafeHarnessReadOnlyValidationCommand(args, scenarioDir);
}

bool _isHarnessShellControlArgument(String value) {
  return value == '&&' || value == '||' || value == ';' || value == '|';
}

bool _matchesHarnessSavedValidationCommand(
  List<String> commandArgs,
  String savedValidationCommand,
) {
  final validationArgs = GitTools.splitArgs(savedValidationCommand.trim());
  if (validationArgs.isEmpty || commandArgs.length < validationArgs.length) {
    return false;
  }
  final exactMatch = _harnessCommandSliceMatches(
    commandArgs,
    validationArgs,
    start: 0,
  );
  if (commandArgs.length == validationArgs.length) {
    return exactMatch;
  }
  final startsWithValidation =
      exactMatch && commandArgs[validationArgs.length] == '&&';
  final suffixStart = commandArgs.length - validationArgs.length;
  final endsWithValidation =
      suffixStart > 0 &&
      commandArgs[suffixStart - 1] == '&&' &&
      _harnessCommandSliceMatches(
        commandArgs,
        validationArgs,
        start: suffixStart,
      );
  return startsWithValidation || endsWithValidation;
}

bool _harnessCommandSliceMatches(
  List<String> commandArgs,
  List<String> expectedArgs, {
  required int start,
}) {
  for (var index = 0; index < expectedArgs.length; index++) {
    if (commandArgs[start + index] != expectedArgs[index]) {
      return false;
    }
  }
  return true;
}

bool _isExactHarnessScenarioRoot(String path, Directory scenarioDir) {
  String normalize(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  return normalize(path) == normalize(scenarioDir.path);
}

bool _isSafeHarnessSavedValidationCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  if (_isSafeHarnessDartProjectCommand(args, scenarioDir)) {
    return true;
  }
  if (_isSafeHarnessReadOnlyPipelineValidationCommand(args, scenarioDir)) {
    return true;
  }
  final segments = <List<String>>[];
  var current = <String>[];
  for (final arg in args) {
    if (arg == '&&') {
      if (current.isEmpty) {
        return false;
      }
      segments.add(current);
      current = <String>[];
      continue;
    }
    if (_isHarnessShellControlArgument(arg)) {
      return false;
    }
    current.add(arg);
  }
  if (current.isEmpty) {
    return false;
  }
  segments.add(current);
  return segments.every(
    (segment) =>
        _isSafeHarnessDartRuntimeInfoCommand(segment) ||
        _isSafeHarnessDartProjectCommand(segment, scenarioDir) ||
        _isSafeHarnessDartCompileValidationCommand(
          segment,
          scenarioDir,
          task,
        ) ||
        _isSafeHarnessDartFormatCommand(segment, scenarioDir, task) ||
        _isSafeHarnessStateResetCommand(segment, scenarioDir, task) ||
        _isSafeHarnessReadOnlyValidationCommand(segment, scenarioDir) ||
        _isSafeHarnessTargetCliProbeCommand(segment, scenarioDir, task),
  );
}

bool _isSafeHarnessDartCompileValidationCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 2) {
      return false;
    }
    command = command.sublist(1);
  }
  if (command.length != 6 ||
      command.first.split('/').last.toLowerCase() != 'dart' ||
      command[1] != 'compile' ||
      command[2] != 'exe' ||
      command[4] != '-o') {
    return false;
  }
  final input = _normalizeHarnessRelativePath(command[3], scenarioDir);
  final targets = task.targetFiles
      .map((path) => _normalizeHarnessRelativePath(path, scenarioDir))
      .whereType<String>()
      .toSet();
  if (input == null || !targets.contains(input)) {
    return false;
  }
  final output = command[5];
  return output == '/dev/null' ||
      _isSafeHarnessCommandPath(output, scenarioDir);
}

bool _isSafeHarnessStateResetCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  if (args.length < 3 || args.first.split('/').last.toLowerCase() != 'rm') {
    return false;
  }
  final paths = <String>[];
  for (final argument in args.skip(1)) {
    if (argument == '-f' || argument == '--force') {
      continue;
    }
    if (argument.startsWith('-')) {
      return false;
    }
    paths.add(argument);
  }
  if (paths.isEmpty) {
    return false;
  }
  final normalizedTargets = task.targetFiles
      .map((path) => _normalizeHarnessRelativePath(path, scenarioDir))
      .whereType<String>()
      .toSet();
  return paths.every((path) {
    final normalized = _normalizeHarnessRelativePath(path, scenarioDir);
    if (normalized == null ||
        normalized.contains('/') ||
        !normalized.toLowerCase().endsWith('.json') ||
        normalizedTargets.contains(normalized)) {
      return false;
    }
    final basename = normalized.toLowerCase();
    return basename != 'heartbeat.json' && basename != 'package_config.json';
  });
}

bool _isSafeHarnessDartRuntimeInfoCommand(List<String> args) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 3) {
      return false;
    }
    command = command.sublist(1);
  }
  final executable = command.first.split('/').last.toLowerCase();
  return (executable == 'dart' || executable == 'flutter') &&
      command.length == 2 &&
      command[1] == '--version';
}

bool _isSafeHarnessDartScaffoldCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 2) {
      return false;
    }
    command = command.sublist(1);
  }
  if (command.length < 3 ||
      command.first.split('/').last.toLowerCase() != 'dart' ||
      command[1] != 'create') {
    return false;
  }

  String? template;
  String? targetPath;
  for (var index = 2; index < command.length; index += 1) {
    final argument = command[index];
    if (argument == '-t' || argument == '--template') {
      if (template != null || index + 1 >= command.length) {
        return false;
      }
      template = command[++index];
      continue;
    }
    if (argument.startsWith('-t=') || argument.startsWith('--template=')) {
      if (template != null) {
        return false;
      }
      template = argument.substring(argument.indexOf('=') + 1);
      continue;
    }
    if (argument == '--force' || argument == '--no-pub') {
      continue;
    }
    if (argument.startsWith('-') || targetPath != null) {
      return false;
    }
    targetPath = argument;
  }

  if (targetPath == null ||
      (template != null &&
          template != 'console' &&
          template != 'console-full')) {
    return false;
  }
  final normalizedTarget = targetPath.replaceAll('\\', '/');
  final normalizedScenarioPath = scenarioDir.path.replaceAll('\\', '/');
  final targetsScenarioRoot =
      normalizedTarget == '.' ||
      normalizedTarget == './' ||
      normalizedTarget == normalizedScenarioPath;
  if (!targetsScenarioRoot) {
    return false;
  }
  return task.targetFiles.any(
    (path) =>
        _normalizeHarnessRelativePath(path, scenarioDir) == 'pubspec.yaml',
  );
}

bool _isSafeHarnessDartProjectCommand(
  List<String> args,
  Directory scenarioDir,
) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 2) {
      return false;
    }
    command = command.sublist(1);
  }
  final executable = command.first.split('/').last.toLowerCase();
  if (executable != 'dart' && executable != 'flutter') {
    return false;
  }
  if (command.length == 3 && command[1] == 'pub' && command[2] == 'get') {
    return true;
  }
  if (command.length < 2 || command[1] != 'analyze') {
    return false;
  }
  const safeFlags = <String>{
    '--fatal-infos',
    '--fatal-warnings',
    '--no-fatal-infos',
    '--no-fatal-warnings',
  };
  return command
      .skip(2)
      .every(
        (argument) =>
            safeFlags.contains(argument) ||
            (!argument.startsWith('-') &&
                _isSafeHarnessCommandPath(argument, scenarioDir)),
      );
}

bool _isSafeHarnessDartFormatCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 3) {
      return false;
    }
    command = command.sublist(1);
  }
  if (command.length < 3 ||
      command.first.split('/').last.toLowerCase() != 'dart' ||
      command[1] != 'format') {
    return false;
  }

  final paths = <String>[];
  for (final argument in command.skip(2)) {
    if (argument == '--set-exit-if-changed') {
      continue;
    }
    if (argument.startsWith('-')) {
      return false;
    }
    paths.add(argument);
  }
  if (paths.isEmpty) {
    return false;
  }

  final normalizedTargets = task.targetFiles
      .map((path) => _normalizeHarnessRelativePath(path, scenarioDir))
      .whereType<String>()
      .where((path) => path.toLowerCase().endsWith('.dart'))
      .toSet();
  if (normalizedTargets.isEmpty) {
    return false;
  }

  for (final path in paths) {
    final normalized = _normalizeHarnessRelativePath(path, scenarioDir);
    if (normalized == null) {
      return false;
    }
    if (normalizedTargets.contains(normalized)) {
      continue;
    }
    final directory = Directory('${scenarioDir.path}/$normalized');
    if (!directory.existsSync() ||
        FileSystemEntity.isLinkSync(directory.path)) {
      return false;
    }
    final entities = directory.listSync(recursive: true, followLinks: false);
    if (entities.whereType<Link>().isNotEmpty) {
      return false;
    }
    final dartFiles = entities
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.dart'))
        .map((file) => _normalizeHarnessRelativePath(file.path, scenarioDir))
        .whereType<String>()
        .toSet();
    if (dartFiles.isEmpty || !normalizedTargets.containsAll(dartFiles)) {
      return false;
    }
  }
  return true;
}

bool _isSafeHarnessDirectoryCreationCommand(
  List<String> args,
  Directory scenarioDir,
) {
  if (args.length < 2 || args.first.split('/').last.toLowerCase() != 'mkdir') {
    return false;
  }
  final paths = <String>[];
  for (final argument in args.skip(1)) {
    if (argument == '-p' || argument == '--parents') {
      continue;
    }
    if (argument.startsWith('-')) {
      return false;
    }
    paths.add(argument);
  }
  return paths.isNotEmpty &&
      paths.every((path) => _isSafeHarnessCommandPath(path, scenarioDir));
}

bool _isSafeHarnessReadOnlyPipelineValidationCommand(
  List<String> args,
  Directory scenarioDir,
) {
  final pipeIndexes = <int>[];
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '|') {
      pipeIndexes.add(index);
      continue;
    }
    if (arg == '&&' || arg == '||' || arg == ';') {
      return false;
    }
  }
  if (pipeIndexes.length != 1) {
    return false;
  }
  final pipeIndex = pipeIndexes.single;
  if (pipeIndex == 0 || pipeIndex == args.length - 1) {
    return false;
  }
  final left = args.sublist(0, pipeIndex);
  final right = args.sublist(pipeIndex + 1);
  return _isSafeHarnessReadOnlyValidationCommand(left, scenarioDir) &&
      _isSafeHarnessStdinGrepCommand(right);
}

bool _isSafeHarnessStdinGrepCommand(List<String> args) {
  if (args.length < 2) {
    return false;
  }
  final executable = args.first.split('/').last.toLowerCase();
  if (executable != 'grep') {
    return false;
  }
  final patternArguments = args
      .skip(1)
      .where((arg) => !arg.startsWith('-'))
      .toList(growable: false);
  return patternArguments.length == 1;
}

bool _isSafeHarnessReadOnlyValidationCommand(
  List<String> args,
  Directory scenarioDir,
) {
  final executable = args.first.split('/').last.toLowerCase();
  if (executable == 'cat' && args.length == 2) {
    return _isSafeHarnessCommandPath(args[1], scenarioDir);
  }
  if (executable == 'ls' && args.length == 2) {
    return _isSafeHarnessCommandPath(args[1], scenarioDir);
  }
  if (executable == 'test' && args.length == 3 && args[1] == '-f') {
    return _isSafeHarnessCommandPath(args[2], scenarioDir);
  }
  if (executable == 'grep' && args.length >= 3) {
    return _isSafeHarnessCommandPath(args.last, scenarioDir);
  }
  return false;
}

bool _isSafeHarnessCommandPath(String path, Directory scenarioDir) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed.startsWith(Platform.pathSeparator)) {
    return _isWithinScenarioWorkspace(trimmed, scenarioDir);
  }
  final segments = trimmed.split(RegExp(r'[/\\]+'));
  return !segments.contains('..');
}

bool _isSafeHarnessTargetCliProbeCommand(
  List<String> args,
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  var command = args;
  if (command.first.split('/').last.toLowerCase() == 'fvm') {
    if (command.length < 3) {
      return false;
    }
    command = command.sublist(1);
  }
  final executable = command.first.split('/').last.toLowerCase();
  late final String scriptPath;
  late final Iterable<String> applicationArguments;
  if ((executable == 'python' || executable == 'python3') &&
      command.length >= 2) {
    scriptPath = command[1];
    applicationArguments = command.skip(2);
  } else if (executable == 'dart' &&
      command.length >= 3 &&
      command[1] == 'run') {
    scriptPath = command[2];
    applicationArguments = command.skip(3);
  } else if (executable == 'dart' && command.length >= 2) {
    scriptPath = command[1];
    applicationArguments = command.skip(2);
  } else {
    return false;
  }
  if (applicationArguments.any(
    (argument) =>
        argument.contains('\n') || argument.contains('\r') || argument == '--',
  )) {
    return false;
  }
  if (!_isSafeHarnessCommandPath(scriptPath, scenarioDir)) {
    return false;
  }
  final normalizedScriptPath = _normalizeHarnessRelativePath(
    scriptPath,
    scenarioDir,
  );
  if (normalizedScriptPath == null) {
    return false;
  }
  return task.targetFiles.any((targetFile) {
    final normalizedTarget = _normalizeHarnessRelativePath(
      targetFile,
      scenarioDir,
    );
    return normalizedTarget != null && normalizedTarget == normalizedScriptPath;
  });
}

String? _normalizeHarnessRelativePath(String path, Directory scenarioDir) {
  var normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty) {
    return null;
  }
  final scenarioPath = scenarioDir.path.replaceAll('\\', '/');
  if (normalized.startsWith('/')) {
    if (normalized == scenarioPath) {
      return null;
    }
    final prefix = '$scenarioPath/';
    if (!normalized.startsWith(prefix)) {
      return null;
    }
    normalized = normalized.substring(prefix.length);
  }
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  final segments = normalized
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty || segments.contains('..')) {
    return null;
  }
  return segments.join('/');
}

bool _isWithinScenarioWorkspace(String path, Directory scenarioDir) {
  if (path.isEmpty) {
    return false;
  }
  final scenarioPath = scenarioDir.path;
  return path == scenarioPath ||
      path.startsWith('$scenarioPath${Platform.pathSeparator}');
}

List<String> missingPlanModeHarnessTargetFiles(
  Directory scenarioDir,
  ConversationWorkflowTask task,
) {
  return task.targetFiles
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .where((path) {
        final file = path.startsWith(Platform.pathSeparator)
            ? File(path)
            : File('${scenarioDir.path}${Platform.pathSeparator}$path');
        return !file.existsSync();
      })
      .toList(growable: false);
}

Future<void> awaitPlanModeHarnessExecutionCleanup(
  PlanModeHarnessExecutionHandle? executionHandle, {
  required String scenarioName,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final executionFuture = executionHandle?.done;
  if (executionFuture == null) {
    return;
  }
  try {
    await executionFuture.timeout(timeout);
  } on TimeoutException {
    executionHandle?.requestCleanupCancellation();
    appLog(
      '[Workflow] Harness background execution did not finish before cleanup '
      'timeout for $scenarioName',
    );
  }
}

bool isPlanModeHarnessProviderContainerDisposedError(Object error) {
  return error is StateError &&
      error.toString().contains(
        'Tried to read a provider from a ProviderContainer that was already disposed',
      );
}

Duration resolvePlanModeHarnessCleanupTimeout({
  required bool usesLiveLlm,
  required PlanModeTimeoutBudgets budgets,
}) {
  if (!usesLiveLlm) {
    return const Duration(seconds: 30);
  }
  const minimumLiveTimeout = Duration(seconds: 90);
  return budgets.executionTimeout > minimumLiveTimeout
      ? budgets.executionTimeout
      : minimumLiveTimeout;
}

String? latestPlanModeHarnessAssistantMessageId(Conversation? conversation) {
  return _latestPlanModeHarnessAssistantMessage(conversation)?.id;
}

String latestPlanModeHarnessAssistantResponseAfter(
  Conversation? conversation,
  String? previousAssistantMessageId,
) {
  final latest = _latestPlanModeHarnessAssistantMessage(conversation);
  if (latest == null || latest.id == previousAssistantMessageId) {
    return '';
  }
  return latest.content.trim();
}

Message? _latestPlanModeHarnessAssistantMessage(Conversation? conversation) {
  if (conversation == null) {
    return null;
  }
  for (final message in conversation.messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message;
    }
  }
  return null;
}

String buildPlanModeHarnessFallbackAssistantResponse({
  required List<ToolResultInfo> toolResults,
  required String? hiddenAssistantResponse,
}) {
  final hidden = hiddenAssistantResponse?.trim() ?? '';
  if (hidden.isNotEmpty) {
    return hidden;
  }
  if (toolResults.isEmpty) {
    return '';
  }
  final toolNames = toolResults
      .map((result) => result.name.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .join(', ');
  if (toolNames.isEmpty) {
    return 'The saved task completed with tool execution evidence.';
  }
  return 'The saved task completed with tool execution evidence from: $toolNames.';
}
