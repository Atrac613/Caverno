import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_coordinator.dart';
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
    cancellationSignal: cancellationSignal,
    send: () {
      if (useHiddenPrompt) {
        return chatNotifier.sendHiddenPrompt(prompt, languageCode: 'en');
      }
      return chatNotifier.sendMessage(
        prompt,
        languageCode: 'en',
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

  await conversationsNotifier
      .updateCurrentExecutionTaskProgressFromAssistantTurn(
        task: task,
        assistantResponse: primaryAssistantResponse,
        isValidationRun: false,
        fallbackAssistantResponse: fallbackResponse,
      );
  return true;
}

Future<void> _sendHarnessPromptWithApprovals(
  ProviderContainer container, {
  required Directory scenarioDir,
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
          _isSafeHarnessLocalCommand(pendingLocalCommand, scenarioDir);
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

bool _isSafeHarnessLocalCommand(
  PendingLocalCommand pending,
  Directory scenarioDir,
) {
  final command = pending.command.trimLeft();
  final usesScenarioWorkspace =
      command.contains(scenarioDir.path) ||
      _isWithinScenarioWorkspace(pending.workingDirectory.trim(), scenarioDir);
  if (!usesScenarioWorkspace) {
    return false;
  }
  return command.startsWith('grep ') || command.startsWith('/usr/bin/grep ');
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
