import 'dart:io';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/conversation_execution_progress_inference.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_execution_guardrails.dart';
import '../../domain/services/conversation_validation_tool_result_inference.dart';
import '../../domain/services/workflow_task_run_lifecycle_policy.dart';
import '../../domain/services/workflow_tool_result_failure_detector.dart';
import '../providers/chat_notifier.dart';
import '../providers/conversations_notifier.dart';

typedef WorkflowTaskStatusUpdater =
    Future<void> Function(WorkflowTaskStatusUpdate update);

final class WorkflowTaskExecutionPromptText {
  const WorkflowTaskExecutionPromptText({
    required this.intro,
    required this.targetFilesLabel,
    required this.validationLabel,
    required this.notesLabel,
    required this.outro,
  });

  final String intro;
  final String targetFilesLabel;
  final String validationLabel;
  final String notesLabel;
  final String outro;
}

final class WorkflowTaskValidationPromptText {
  const WorkflowTaskValidationPromptText({
    required this.intro,
    required this.targetFilesLabel,
    required this.validationLabel,
    required this.outro,
  });

  final String intro;
  final String targetFilesLabel;
  final String validationLabel;
  final String outro;
}

final class WorkflowTaskStatusUpdate {
  const WorkflowTaskStatusUpdate({
    required this.currentConversation,
    required this.task,
    required this.status,
    this.summary = '',
    this.lastRunAt,
    this.lastValidationAt,
    this.validationStatus,
    this.blockedReason,
    this.lastValidationCommand,
    this.lastValidationSummary,
    this.eventType,
  });

  final Conversation currentConversation;
  final ConversationWorkflowTask task;
  final ConversationWorkflowTaskStatus status;
  final String summary;
  final DateTime? lastRunAt;
  final DateTime? lastValidationAt;
  final ConversationExecutionValidationStatus? validationStatus;
  final String? blockedReason;
  final String? lastValidationCommand;
  final String? lastValidationSummary;
  final ConversationExecutionTaskEventType? eventType;
}

final class WorkflowTaskRunCoordinator {
  WorkflowTaskRunCoordinator({
    required ChatNotifier chatNotifier,
    required ConversationsNotifier conversationsNotifier,
    required Conversation? Function() readCurrentConversation,
    required String? Function() readActiveProjectRoot,
    required WorkflowTaskStatusUpdater updateTaskStatus,
    required bool Function() isPageMounted,
    required bool Function() isContextMounted,
    required DateTime Function() now,
  }) : _chatNotifier = chatNotifier,
       _conversationsNotifier = conversationsNotifier,
       _readCurrentConversation = readCurrentConversation,
       _readActiveProjectRoot = readActiveProjectRoot,
       _updateTaskStatus = updateTaskStatus,
       _isPageMounted = isPageMounted,
       _isContextMounted = isContextMounted,
       _now = now;

  final ChatNotifier _chatNotifier;
  final ConversationsNotifier _conversationsNotifier;
  final Conversation? Function() _readCurrentConversation;
  final String? Function() _readActiveProjectRoot;
  final WorkflowTaskStatusUpdater _updateTaskStatus;
  final bool Function() _isPageMounted;
  final bool Function() _isContextMounted;
  final DateTime Function() _now;

  Future<void> _setWorkflowTaskStatus({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required ConversationWorkflowTaskStatus status,
    String summary = '',
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
  }) => _updateTaskStatus(
    WorkflowTaskStatusUpdate(
      currentConversation: currentConversation,
      task: task,
      status: status,
      summary: summary,
      lastRunAt: lastRunAt,
      lastValidationAt: lastValidationAt,
      validationStatus: validationStatus,
      blockedReason: blockedReason,
      lastValidationCommand: lastValidationCommand,
      lastValidationSummary: lastValidationSummary,
      eventType: eventType,
    ),
  );

  Future<void> runTask({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required String languageCode,
    required WorkflowTaskExecutionPromptText promptText,
  }) async {
    final previousAssistantMessageId = _latestAssistantMessageId(
      _readCurrentConversation() ?? currentConversation,
    );

    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
      summary: task.status == ConversationWorkflowTaskStatus.completed
          ? 'Reopened the completed task for review.'
          : 'Started from the approved plan execution flow.',
      lastRunAt: task.status == ConversationWorkflowTaskStatus.completed
          ? null
          : _now(),
      eventType: task.status == ConversationWorkflowTaskStatus.completed
          ? null
          : ConversationExecutionTaskEventType.started,
    );
    if (!_isContextMounted()) {
      return;
    }

    await _chatNotifier.sendMessage(
      ConversationPlanExecutionCoordinator.buildTaskPrompt(
        task: task,
        intro: promptText.intro,
        targetFilesLabel: promptText.targetFilesLabel,
        validationLabel: promptText.validationLabel,
        notesLabel: promptText.notesLabel,
        outro: promptText.outro,
      ),
      languageCode: languageCode,
      bypassPlanMode: true,
    );
    if (!_isPageMounted() || !_isContextMounted()) {
      return;
    }

    await _processTaskTurnResults(
      task: task,
      languageCode: languageCode,
      previousAssistantMessageId: previousAssistantMessageId,
    );
    if (!_isContextMounted()) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(
      completedTask: task,
      languageCode: languageCode,
    );
  }

  Future<void> runValidation({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required String languageCode,
    required WorkflowTaskValidationPromptText promptText,
  }) async {
    final previousAssistantMessageId = _latestAssistantMessageId(
      _readCurrentConversation() ?? currentConversation,
    );
    final validationCommand = task.validationCommand.trim();
    final validationStartedAt = _now();
    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: task,
      status: task.status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowTaskStatus.completed
          : ConversationWorkflowTaskStatus.inProgress,
      summary: 'Ran the saved validation step from the approved plan.',
      lastValidationAt: validationStartedAt,
      validationStatus: ConversationExecutionValidationStatus.unknown,
      lastValidationCommand: validationCommand,
      lastValidationSummary: validationCommand.isEmpty
          ? 'Started validation using the saved task context.'
          : 'Started validation with the saved command.',
    );
    if (!_isContextMounted()) {
      return;
    }

    await _chatNotifier.sendMessage(
      ConversationPlanExecutionCoordinator.buildValidationPrompt(
        task: task,
        intro: promptText.intro,
        targetFilesLabel: promptText.targetFilesLabel,
        validationLabel: promptText.validationLabel,
        outro: promptText.outro,
      ),
      languageCode: languageCode,
      bypassPlanMode: true,
    );
    if (!_isPageMounted() || !_isContextMounted()) {
      return;
    }
    final validationToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied = await _conversationsNotifier
        .updateCurrentValidationProgressFromToolResults(
          task: task,
          toolResults: validationToolResults
              .map(
                (result) => ConversationValidationToolResultInput(
                  toolName: result.name,
                  rawResult: result.result,
                ),
              )
              .toList(growable: false),
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: task,
            toolResults: validationToolResults,
          )
        : false;
    final recoveredFromMissingTarget =
        toolResultApplied &&
        !completionPromoted &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonRuntimeDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonRuntimeDependency(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonTestDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    final recoveredFromPythonImport =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: validationToolResults,
        );
    if (!toolResultApplied ||
        (!completionPromoted &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonRuntimeDependency &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport)) {
      await _captureExecutionProgressFromLatestAssistantEvidence(
        task: task,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: true,
        fallbackAssistantResponse: _chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }
    if (!_isContextMounted()) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(
      completedTask: task,
      languageCode: languageCode,
    );
  }

  Future<void> _continueToNextPendingTaskIfNeeded({
    required ConversationWorkflowTask completedTask,
    required String languageCode,
    int depth = 0,
  }) async {
    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return;
    }
    final selection = WorkflowTaskRunLifecyclePolicy.selectAutoContinuation(
      conversation: currentConversation,
      completedTaskId: completedTask.id,
      continuationDepth: depth,
    );
    if (selection == null) {
      return;
    }
    final latestCompletedTask = selection.completedTask;
    final nextTask = selection.nextTask;

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _setWorkflowTaskStatus(
      currentConversation: currentConversation,
      task: nextTask,
      status: ConversationWorkflowTaskStatus.inProgress,
      summary:
          'Auto-continued to the next saved task after completing "${latestCompletedTask.title}".',
      lastRunAt: _now(),
      eventType: ConversationExecutionTaskEventType.started,
    );

    if (!_isContextMounted()) {
      return;
    }

    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildAutoContinueTaskPrompt(
        completedTask: latestCompletedTask,
        nextTask: nextTask,
      ),
      languageCode: languageCode,
    );
    if (!_isContextMounted()) {
      return;
    }
    await _processTaskTurnResults(
      task: nextTask,
      languageCode: languageCode,
      previousAssistantMessageId: previousAssistantMessageId,
    );
    if (!_isContextMounted()) {
      return;
    }
    await _continueToNextPendingTaskIfNeeded(
      completedTask: nextTask,
      languageCode: languageCode,
      depth: depth + 1,
    );
  }

  Future<void> _processTaskTurnResults({
    required ConversationWorkflowTask task,
    required String languageCode,
    required String? previousAssistantMessageId,
  }) async {
    final toolResults = _chatNotifier.takeLatestToolResults();
    final hiddenAssistantResponse = _chatNotifier
        .takeLatestHiddenAssistantResponse();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: task,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: toolResults,
          fallbackAssistantResponse: hiddenAssistantResponse,
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: task,
            toolResults: toolResults,
          )
        : false;
    final recoveredFromValidation =
        !toolResultApplied &&
        await _maybeRecoverFromValidationFirstExecution(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromFailure =
        !toolResultApplied &&
        !recoveredFromValidation &&
        await _maybeRecoverFromToolFailureSignals(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromMissingTarget =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonRuntimeDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonRuntimeDependency(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonTestDependency =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromPythonImport =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final recoveredFromDrift =
        !toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        await _maybeRecoverFromTaskDrift(
          task: task,
          languageCode: languageCode,
          toolResults: toolResults,
        );
    final assistantEvidenceApplied =
        !completionPromoted &&
            !recoveredFromValidation &&
            !recoveredFromFailure &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonRuntimeDependency &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport &&
            !recoveredFromDrift
        ? await _captureExecutionProgressFromLatestAssistantEvidence(
            task: task,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse:
                hiddenAssistantResponse ??
                _chatNotifier.takeLatestHiddenAssistantResponse(),
          )
        : false;
    if (!toolResultApplied &&
        !recoveredFromValidation &&
        !recoveredFromFailure &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonRuntimeDependency &&
        !recoveredFromPythonTestDependency &&
        !recoveredFromPythonImport &&
        !recoveredFromDrift) {
      await _maybeRecoverFromToolLessExecution(
        task: task,
        languageCode: languageCode,
        toolResults: toolResults,
        assistantEvidenceApplied: assistantEvidenceApplied,
        fallbackAssistantResponse:
            hiddenAssistantResponse ??
            _chatNotifier.takeLatestHiddenAssistantResponse(),
      );
    }
  }

  String? _activeProjectRootPath() => _readActiveProjectRoot();

  List<String> _existingWorkspaceTargetFiles(ConversationWorkflowTask task) {
    final projectRoot = _activeProjectRootPath();
    if (projectRoot == null || projectRoot.isEmpty) {
      return const <String>[];
    }

    final existingTargets = <String>[];
    for (final target
        in ConversationPlanExecutionGuardrails.effectiveTargetPathsForTask(
          task,
        )) {
      final normalizedTarget = target.trim().replaceAll('\\', '/');
      if (normalizedTarget.isEmpty) {
        continue;
      }
      final resolvedPath = normalizedTarget.startsWith('/')
          ? normalizedTarget
          : '$projectRoot/$normalizedTarget';
      if (File(resolvedPath).existsSync() ||
          Directory(resolvedPath).existsSync()) {
        existingTargets.add(normalizedTarget);
      }
    }
    return existingTargets.toList(growable: false);
  }

  Future<bool> _maybeFinalizeScaffoldFromWorkspaceTargets({
    required ConversationWorkflowTask task,
  }) async {
    final existingTargetFiles = _existingWorkspaceTargetFiles(task);
    final canFinalize =
        ConversationPlanExecutionGuardrails.canFinalizeScaffoldFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingTargetFiles,
        );
    if (!canFinalize) {
      return false;
    }

    final validationCommand = task.validationCommand.trim();
    const summary =
        'Marked complete after confirming every scaffold target file existed in the workspace.';
    await _conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: summary,
      validationStatus: validationCommand.isEmpty
          ? ConversationExecutionValidationStatus.unknown
          : ConversationExecutionValidationStatus.passed,
      lastValidationAt: validationCommand.isEmpty ? null : _now(),
      lastValidationCommand: validationCommand.isEmpty
          ? null
          : validationCommand,
      lastValidationSummary: validationCommand.isEmpty ? null : summary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: summary,
    );
    return true;
  }

  Future<bool> _maybeRecoverFromTaskDrift({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
      task: task,
      toolResults: toolResults,
      changedFilePaths: _latestTurnChangedFilePaths(),
    );
    if (!assessment.hasDrift) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildTaskDriftRecoveryPrompt(
        task: latestTask,
        unrelatedTouchedPaths: assessment.unrelatedTouchedPaths,
        scaffoldCommands: assessment.scaffoldCommands,
        alreadyTouchedTargetFiles: assessment.touchedTargetFiles,
        repeatedTargetFiles: assessment.repeatedTargetFiles,
        remainingTargetFiles: assessment.remainingTargetFiles,
      ),
      languageCode: languageCode,
    );

    return _captureExecutionProgressFromLatestToolResults(
      task: latestTask,
      previousAssistantMessageId: previousAssistantMessageId,
      toolResults: _chatNotifier.takeLatestToolResults(),
    );
  }

  Future<bool> _maybeRecoverFromToolFailureSignals({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        !WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final existingTargetFiles = _existingWorkspaceTargetFiles(latestTask);
    final missingTargetFiles =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        );
    final isScaffoldTask =
        ConversationPlanExecutionGuardrails.looksLikeScaffoldTask(latestTask);
    final unavailableToolNames =
        ConversationPlanExecutionGuardrails.unavailableToolNames(toolResults);
    final editMismatchPaths =
        ConversationPlanExecutionGuardrails.editMismatchPaths(toolResults);
    final malformedFileMutationPaths =
        ConversationPlanExecutionGuardrails.malformedFileMutationPaths(
          toolResults,
        );
    final hasMalformedFileMutationFailure =
        ConversationPlanExecutionGuardrails.hasMalformedFileMutationFailure(
          toolResults,
        );
    final shouldAttemptScaffoldRecovery =
        isScaffoldTask && missingTargetFiles.isNotEmpty;
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        !shouldAttemptScaffoldRecovery) {
      return false;
    }
    if (unavailableToolNames.isEmpty &&
        editMismatchPaths.isEmpty &&
        !hasMalformedFileMutationFailure &&
        !shouldAttemptScaffoldRecovery) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      shouldAttemptScaffoldRecovery
          ? existingTargetFiles.isEmpty
                ? ConversationPlanExecutionCoordinator.buildScaffoldMissingTargetRecoveryPrompt(
                    task: latestTask,
                    missingTargetFiles: missingTargetFiles,
                  )
                : ConversationPlanExecutionCoordinator.buildScaffoldRemainingTargetRecoveryPrompt(
                    task: latestTask,
                    existingTargetFiles: existingTargetFiles,
                    missingTargetFiles: missingTargetFiles,
                  )
          : ConversationPlanExecutionCoordinator.buildToolFailureRecoveryPrompt(
              task: latestTask,
              unavailableToolNames: unavailableToolNames,
              editMismatchPaths: editMismatchPaths,
              malformedFileMutationPaths: malformedFileMutationPaths,
              hasMalformedFileMutationFailure: hasMalformedFileMutationFailure,
            ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    final completionPromoted = toolResultApplied
        ? await _maybePromoteCompletionFromValidationToolResults(
            task: latestTask,
            toolResults: recoveryToolResults,
          )
        : false;
    final recoveredFromMissingTarget =
        toolResultApplied &&
        !completionPromoted &&
        await _maybeRecoverFromMissingTargetValidationFailure(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final recoveredFromPythonTestDependency =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        await _maybeRecoverFromMissingPythonTestDependency(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final recoveredFromPythonImport =
        toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonTestDependency &&
        await _maybeRecoverFromPythonSrcLayoutValidationFailure(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    final onlyReadMismatchedFiles =
        editMismatchPaths.isNotEmpty &&
        recoveryToolResults.isNotEmpty &&
        recoveryToolResults.every((toolResult) {
          if (toolResult.name != 'read_file') {
            return false;
          }
          final path =
              toolResult.arguments['path']?.toString().trim().replaceAll(
                '\\',
                '/',
              ) ??
              '';
          return editMismatchPaths.any((candidate) => candidate == path);
        });
    if (!toolResultApplied &&
        !completionPromoted &&
        !recoveredFromMissingTarget &&
        !recoveredFromPythonImport &&
        onlyReadMismatchedFiles) {
      await _chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildEditMismatchRetryPrompt(
          task: latestTask,
          editMismatchPaths: editMismatchPaths,
        ),
        languageCode: languageCode,
      );

      final retryToolResults = _chatNotifier.takeLatestToolResults();
      final retryApplied = await _captureExecutionProgressFromLatestToolResults(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        toolResults: retryToolResults,
      );
      if (retryApplied || _taskReachedTerminalStatus(latestTask.id)) {
        return true;
      }
    }
    if (!toolResultApplied ||
        (!completionPromoted &&
            !recoveredFromMissingTarget &&
            !recoveredFromPythonTestDependency &&
            !recoveredFromPythonImport)) {
      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: _chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult && recoveryToolResults.isEmpty) {
        return false;
      }
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingTargetValidationFailure({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        !WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final missingTargetFile =
        ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingTargetFile == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
        task: latestTask,
        missingTargetFiles: [missingTargetFile],
        failedCommand: failedCommand,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    final recoveredFromValidation =
        !toolResultApplied &&
        await _maybeRecoverFromValidationFirstExecution(
          task: latestTask,
          languageCode: languageCode,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied ||
        recoveredFromValidation ||
        _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingPythonTestDependency({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        !WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final missingDependency =
        ConversationPlanExecutionGuardrails.missingPythonTestDependency(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingDependency == null) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();
    final fallbackCommand =
        ConversationPlanExecutionGuardrails.suggestPythonTestDependencyFallbackCommand(
          task: latestTask,
          failedCommand: failedCommand,
          missingDependency: missingDependency,
        );
    if (fallbackCommand == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonTestDependencyRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        fallbackCommand: fallbackCommand,
        missingDependency: missingDependency,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromMissingPythonRuntimeDependency({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        !WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final missingDependency =
        ConversationPlanExecutionGuardrails.missingPythonRuntimeDependency(
          task: latestTask,
          toolResults: toolResults,
        );
    if (missingDependency == null) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        ) ??
        latestTask.validationCommand.trim();

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonRuntimeDependencyRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        missingDependency: missingDependency,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult && recoveryToolResults.isEmpty) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromValidationFirstExecution({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked ||
        latestTask.validationCommand.trim().isEmpty) {
      return false;
    }

    final missingWorkspaceTargets =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: _existingWorkspaceTargetFiles(latestTask),
        );
    if (missingWorkspaceTargets.isNotEmpty) {
      return false;
    }

    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: latestTask,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    if (completionAssessment.hasFailure ||
        completionAssessment.touchedTargetFiles.isEmpty ||
        completionAssessment.successfulValidationCommands.isNotEmpty ||
        completionAssessment.failedValidationCommands.isNotEmpty ||
        completionAssessment.unrelatedTouchedPaths.isNotEmpty ||
        completionAssessment.scaffoldCommands.isNotEmpty) {
      return false;
    }

    final preferValidationNow =
        completionAssessment.touchedAllTargetFiles ||
        completionAssessment.allowsLightValidationCompletion ||
        completionAssessment.untouchedTargetFiles.length <= 1;
    final targetCoverageLooksReady =
        completionAssessment.touchedTargetFiles.isNotEmpty &&
        (completionAssessment.touchedAllTargetFiles ||
            completionAssessment.touchedTargetFiles.length >=
                completionAssessment.untouchedTargetFiles.length);
    if (!preferValidationNow && !targetCoverageLooksReady) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildValidationFirstRecoveryPrompt(
        task: latestTask,
        touchedTargetFiles: completionAssessment.touchedTargetFiles,
        remainingTargetFiles: completionAssessment.untouchedTargetFiles,
        preferValidationNow: preferValidationNow,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybeRecoverFromToolLessExecution({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
    required bool assistantEvidenceApplied,
    String? fallbackAssistantResponse,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isNotEmpty &&
        !ConversationPlanExecutionGuardrails.hasOnlySyntheticNonExecutionResults(
          toolResults,
        )) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final progress = currentConversation.executionProgressForTask(
      latestTask.id,
    );
    final existingTargetFiles = _existingWorkspaceTargetFiles(latestTask);
    final fallbackAssistantEvidence = fallbackAssistantResponse?.trim() ?? '';
    final missingTargetFiles =
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        );
    final isScaffoldTask =
        ConversationPlanExecutionGuardrails.looksLikeScaffoldTask(latestTask);
    if (await _maybeFinalizeScaffoldFromWorkspaceTargets(task: latestTask)) {
      return true;
    }
    final latestAssistantResponse =
        _latestAssistantMessage(currentConversation)?.content.trim() ?? '';
    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: latestTask,
      isValidationRun: false,
      fallbackAssistantResponse: fallbackAssistantEvidence,
    );
    final assistantResponses =
        [latestAssistantResponse, fallbackAssistantEvidence]
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final completionEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskCompletionInAnyResponse(
          task: latestTask,
          assistantResponses: assistantResponses,
        );
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        missingTargetFiles.isEmpty) {
      if (completionEvidence &&
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
            task: latestTask,
            existingTargetPaths: existingTargetFiles,
          )) {
        final summary = assistantInference.summary.isNotEmpty
            ? assistantInference.summary
            : progress?.normalizedValidationSummary ??
                  progress?.normalizedSummary ??
                  'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
        await _conversationsNotifier.updateCurrentExecutionTaskProgress(
          taskId: latestTask.id,
          status: ConversationWorkflowTaskStatus.completed,
          summary: summary,
          validationStatus:
              progress?.validationStatus ==
                  ConversationExecutionValidationStatus.passed
              ? ConversationExecutionValidationStatus.passed
              : null,
          lastValidationAt:
              progress?.validationStatus ==
                  ConversationExecutionValidationStatus.passed
              ? _now()
              : null,
          lastValidationCommand: progress?.normalizedValidationCommand,
          lastValidationSummary:
              progress?.validationStatus ==
                  ConversationExecutionValidationStatus.passed
              ? (progress?.normalizedValidationSummary ?? summary)
              : null,
          eventType: ConversationExecutionTaskEventType.completed,
          eventSummary: summary,
        );
        return true;
      }
      return false;
    }
    if (isScaffoldTask && missingTargetFiles.isNotEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      await _chatNotifier.sendHiddenPrompt(
        existingTargetFiles.isEmpty
            ? ConversationPlanExecutionCoordinator.buildScaffoldMissingTargetRecoveryPrompt(
                task: latestTask,
                missingTargetFiles: missingTargetFiles,
              )
            : ConversationPlanExecutionCoordinator.buildScaffoldRemainingTargetRecoveryPrompt(
                task: latestTask,
                existingTargetFiles: existingTargetFiles,
                missingTargetFiles: missingTargetFiles,
              ),
        languageCode: languageCode,
      );

      final recoveryToolResults = _chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      final recoveredFromValidation =
          !toolResultApplied &&
          await _maybeRecoverFromValidationFirstExecution(
            task: latestTask,
            languageCode: languageCode,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied || recoveredFromValidation) {
        return true;
      }

      return _captureExecutionProgressFromLatestAssistantEvidence(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
        fallbackAssistantResponse: _chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }
    if (!isScaffoldTask && missingTargetFiles.isNotEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      await _chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
          task: latestTask,
          missingTargetFiles: missingTargetFiles,
          failedCommand: latestTask.validationCommand.trim(),
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = _chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied) {
        return true;
      }

      return _captureExecutionProgressFromLatestAssistantEvidence(
        task: latestTask,
        previousAssistantMessageId: previousAssistantMessageId,
        isValidationRun: false,
        fallbackAssistantResponse: _chatNotifier
            .takeLatestHiddenAssistantResponse(),
      );
    }

    final isVerificationTask =
        ConversationPlanExecutionCoordinator.looksLikeVerificationTask(
          latestTask,
        );
    if (isVerificationTask &&
        latestTask.validationCommand.trim().isNotEmpty &&
        missingTargetFiles.isEmpty) {
      final previousAssistantMessageId = _latestAssistantMessageId(
        currentConversation,
      );
      await _chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildVerificationTaskRecoveryPrompt(
          task: latestTask,
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = _chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
        return true;
      }

      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: _chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult) {
        return false;
      }

      if (!_isPageMounted()) {
        return false;
      }
      final refreshedConversation = _readCurrentConversation();
      if (refreshedConversation == null) {
        return false;
      }
      final refreshedTask = refreshedConversation.projectedExecutionTasks
          .where((item) => item.id == latestTask.id)
          .firstOrNull;
      if (refreshedTask == null) {
        return false;
      }
      return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
          refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
    }

    if (assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: latestTask,
          existingTargetPaths: existingTargetFiles,
        )) {
      final summary = assistantInference.summary.isNotEmpty
          ? assistantInference.summary
          : progress?.normalizedValidationSummary ??
                progress?.normalizedSummary ??
                'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: latestTask.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
        validationStatus:
            progress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? ConversationExecutionValidationStatus.passed
            : null,
        lastValidationAt:
            progress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? _now()
            : null,
        lastValidationCommand: progress?.normalizedValidationCommand,
        lastValidationSummary:
            progress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? (progress?.normalizedValidationSummary ?? summary)
            : null,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary,
      );
      return true;
    }
    if (latestTask.status == ConversationWorkflowTaskStatus.blocked &&
        missingTargetFiles.isNotEmpty) {
      return false;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.completed ||
        assistantInference.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }
    if (assistantEvidenceApplied &&
        latestAssistantResponse.isEmpty &&
        fallbackAssistantEvidence.isEmpty) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    if (progress?.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        latestTask.validationCommand.trim().isNotEmpty &&
        missingTargetFiles.isEmpty) {
      await _chatNotifier.sendHiddenPrompt(
        ConversationPlanExecutionCoordinator.buildFailedValidationRecoveryPrompt(
          task: latestTask,
          failedCommand:
              progress?.normalizedValidationCommand ??
              latestTask.validationCommand.trim(),
          failedValidationSummary:
              progress?.normalizedValidationSummary ??
              progress?.normalizedSummary,
        ),
        languageCode: languageCode,
      );

      final recoveryToolResults = _chatNotifier.takeLatestToolResults();
      final toolResultApplied =
          await _captureExecutionProgressFromLatestToolResults(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            toolResults: recoveryToolResults,
          );
      if (toolResultApplied) {
        return true;
      }

      final assistantResult =
          await _captureExecutionProgressFromLatestAssistantEvidence(
            task: latestTask,
            previousAssistantMessageId: previousAssistantMessageId,
            isValidationRun: false,
            fallbackAssistantResponse: _chatNotifier
                .takeLatestHiddenAssistantResponse(),
          );
      if (!assistantResult) {
        return false;
      }

      if (!_isPageMounted()) {
        return false;
      }
      final refreshedConversation = _readCurrentConversation();
      if (refreshedConversation == null) {
        return false;
      }
      final refreshedTask = refreshedConversation.projectedExecutionTasks
          .where((item) => item.id == latestTask.id)
          .firstOrNull;
      if (refreshedTask == null) {
        return false;
      }
      return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
          refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
    }

    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
        task: latestTask,
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _maybePromoteCompletionFromValidationToolResults({
    required ConversationWorkflowTask task,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed) {
      return false;
    }

    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: latestTask,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    final existingWorkspaceTargets = _existingWorkspaceTargetFiles(latestTask);
    final canPromote =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceValidation(
          task: latestTask,
          toolResults: toolResults,
          existingTargetPaths: existingWorkspaceTargets,
        ) ||
        ConversationPlanExecutionGuardrails.canPromoteScaffoldCompletionFromWorkspaceValidation(
          task: latestTask,
          toolResults: toolResults,
          existingTargetPaths: existingWorkspaceTargets,
        );
    if (!canPromote) {
      return false;
    }

    final progress = currentConversation.executionProgressForTask(
      latestTask.id,
    );
    final summary =
        progress?.normalizedValidationSummary ??
        progress?.normalizedSummary ??
        'Marked complete after the saved validation succeeded and every target file existed in the workspace.';
    await _markTaskCompletedFromToolEvidence(
      task: latestTask,
      conversationsNotifier: _conversationsNotifier,
      completionAssessment: completionAssessment,
      summary: summary,
    );
    return true;
  }

  Future<bool> _maybeRecoverFromPythonSrcLayoutValidationFailure({
    required ConversationWorkflowTask task,
    required String languageCode,
    required List<ToolResultInfo> toolResults,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty ||
        !WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestTask = currentConversation.projectedExecutionTasks
        .where((item) => item.id == task.id)
        .firstOrNull;
    if (latestTask == null ||
        latestTask.status == ConversationWorkflowTaskStatus.completed ||
        latestTask.status == ConversationWorkflowTaskStatus.blocked) {
      return false;
    }

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: latestTask,
          toolResults: toolResults,
        );
    if (failedCommand == null) {
      return false;
    }

    final retryCommand =
        ConversationPlanExecutionGuardrails.suggestPythonSrcLayoutRetryCommand(
          task: latestTask,
          failedCommand: failedCommand,
        );
    if (retryCommand == null) {
      return false;
    }

    final previousAssistantMessageId = _latestAssistantMessageId(
      currentConversation,
    );
    await _chatNotifier.sendHiddenPrompt(
      ConversationPlanExecutionCoordinator.buildPythonSrcLayoutValidationRecoveryPrompt(
        task: latestTask,
        failedCommand: failedCommand,
        retryCommand: retryCommand,
        blockedModuleName:
            ConversationPlanExecutionGuardrails.blockedPythonImportModule(
              toolResults,
            ),
      ),
      languageCode: languageCode,
    );

    final recoveryToolResults = _chatNotifier.takeLatestToolResults();
    final toolResultApplied =
        await _captureExecutionProgressFromLatestToolResults(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          toolResults: recoveryToolResults,
        );
    if (toolResultApplied || _taskReachedTerminalStatus(latestTask.id)) {
      return true;
    }

    final assistantResult =
        await _captureExecutionProgressFromLatestAssistantEvidence(
          task: latestTask,
          previousAssistantMessageId: previousAssistantMessageId,
          isValidationRun: false,
          fallbackAssistantResponse: _chatNotifier
              .takeLatestHiddenAssistantResponse(),
        );
    if (!assistantResult) {
      return false;
    }

    if (!_isPageMounted()) {
      return false;
    }
    final refreshedConversation = _readCurrentConversation();
    if (refreshedConversation == null) {
      return false;
    }
    final refreshedTask = refreshedConversation.projectedExecutionTasks
        .where((item) => item.id == latestTask.id)
        .firstOrNull;
    if (refreshedTask == null) {
      return false;
    }
    return refreshedTask.status == ConversationWorkflowTaskStatus.completed ||
        refreshedTask.status == ConversationWorkflowTaskStatus.blocked;
  }

  Future<bool> _captureExecutionProgressFromLatestAssistantEvidence({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestAssistantMessage = _latestAssistantMessage(currentConversation);
    final latestAssistantResponse =
        latestAssistantMessage != null &&
            latestAssistantMessage.id != previousAssistantMessageId
        ? latestAssistantMessage.content
        : '';
    final fallback = fallbackAssistantResponse?.trim() ?? '';
    if (latestAssistantResponse.trim().isEmpty && fallback.isEmpty) {
      return false;
    }

    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: task,
      isValidationRun: isValidationRun,
      fallbackAssistantResponse: fallback,
    );
    final futureTaskTitles = currentConversation.projectedExecutionTasks
        .where((item) => item.id != task.id)
        .where(
          (item) => item.status != ConversationWorkflowTaskStatus.completed,
        )
        .map((item) => item.title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    final assistantResponses = [latestAssistantResponse, fallback]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final completionEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskCompletionInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
        );
    final handoffEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoffInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
          futureTaskTitles: futureTaskTitles,
        );
    if (!isValidationRun &&
        completionEvidence &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: _existingWorkspaceTargetFiles(task),
        )) {
      final currentProgress = currentConversation.executionProgressForTask(
        task.id,
      );
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant confirmed the saved task and every current target file already existed in the workspace.';
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
        validationStatus:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? ConversationExecutionValidationStatus.passed
            : null,
        lastValidationAt:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? _now()
            : null,
        lastValidationCommand:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationCommand
            : null,
        lastValidationSummary:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationSummary
            : null,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary,
      );
      return true;
    }
    if (!isValidationRun &&
        handoffEvidence &&
        assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: _existingWorkspaceTargetFiles(task),
        )) {
      final currentProgress = currentConversation.executionProgressForTask(
        task.id,
      );
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: assistantInference.summary,
        validationStatus:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? ConversationExecutionValidationStatus.passed
            : null,
        lastValidationAt:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? _now()
            : null,
        lastValidationCommand:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationCommand
            : null,
        lastValidationSummary:
            currentProgress?.validationStatus ==
                ConversationExecutionValidationStatus.passed
            ? currentProgress?.normalizedValidationSummary
            : null,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: assistantInference.summary,
      );
      return true;
    }

    await _conversationsNotifier
        .updateCurrentExecutionTaskProgressFromAssistantTurn(
          task: task,
          assistantResponse: latestAssistantResponse,
          isValidationRun: isValidationRun,
          fallbackAssistantResponse: fallback,
        );
    return true;
  }

  Future<bool> _captureExecutionProgressFromLatestToolResults({
    required ConversationWorkflowTask task,
    required String? previousAssistantMessageId,
    required List<ToolResultInfo> toolResults,
    String? fallbackAssistantResponse,
  }) async {
    if (!_isPageMounted()) {
      return false;
    }
    if (toolResults.isEmpty) {
      return false;
    }

    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return false;
    }

    final latestAssistantMessage = _latestAssistantMessage(currentConversation);
    final latestAssistantResponse =
        latestAssistantMessage == null ||
            latestAssistantMessage.id == previousAssistantMessageId
        ? ''
        : latestAssistantMessage.content;
    final fallbackAssistantEvidence = fallbackAssistantResponse?.trim() ?? '';
    final assistantInference = ConversationExecutionProgressInference.infer(
      assistantResponse: latestAssistantResponse,
      task: task,
      isValidationRun: false,
      fallbackAssistantResponse: fallbackAssistantEvidence,
    );
    final completionAssessment =
        ConversationPlanExecutionGuardrails.assessTaskCompletion(
          task: task,
          toolResults: toolResults,
          changedFilePaths: _latestTurnChangedFilePaths(),
        );
    final existingWorkspaceTargets = _existingWorkspaceTargetFiles(task);
    final futureTaskTitles = currentConversation.projectedExecutionTasks
        .where((item) => item.id != task.id)
        .where(
          (item) => item.status != ConversationWorkflowTaskStatus.completed,
        )
        .map((item) => item.title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    final assistantResponses =
        [latestAssistantResponse, fallbackAssistantEvidence]
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final handoffAssistantResponse = assistantResponses.firstWhere(
      (response) =>
          ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoff(
            task: task,
            assistantResponse: response,
            futureTaskTitles: futureTaskTitles,
          ),
      orElse: () => latestAssistantResponse.isNotEmpty
          ? latestAssistantResponse
          : fallbackAssistantEvidence,
    );
    final handoffEvidence =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoffInAnyResponse(
          task: task,
          assistantResponses: assistantResponses,
          futureTaskTitles: futureTaskTitles,
        );
    final currentProgress = currentConversation.executionProgressForTask(
      task.id,
    );
    final currentValidationHandoffEvidence =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromCurrentValidationHandoff(
          task: task,
          toolResults: toolResults,
          assistantResponse: handoffAssistantResponse,
          futureTaskTitles: futureTaskTitles,
        );
    final historicalValidationHandoffEvidence =
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromHistoricalValidationHandoff(
          task: task,
          progress: currentProgress,
          assistantResponse: handoffAssistantResponse,
          futureTaskTitles: futureTaskTitles,
        );
    final onlyRecoverableMalformedFailures =
        ConversationPlanExecutionGuardrails.hasOnlyRecoverableMalformedFailures(
          toolResults,
        );
    final onlyUnavailableToolFailures =
        ConversationPlanExecutionGuardrails.hasOnlyUnavailableToolFailures(
          toolResults,
        );
    final recoverableMissingTargetFile =
        ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
          task: task,
          toolResults: toolResults,
        );
    final validationToolInference =
        ConversationValidationToolResultInference.infer(
          task: task,
          toolResults: toolResults
              .map(
                (result) => ConversationValidationToolResultInput(
                  toolName: result.name,
                  rawResult: result.result,
                ),
              )
              .toList(growable: false),
        );
    if (validationToolInference != null &&
        (validationToolInference.status ==
                ConversationWorkflowTaskStatus.completed ||
            validationToolInference.validationStatus ==
                ConversationExecutionValidationStatus.passed)) {
      final validationProgressUpdated = await _conversationsNotifier
          .updateCurrentValidationProgressFromToolResults(
            task: task,
            toolResults: toolResults
                .map(
                  (result) => ConversationValidationToolResultInput(
                    toolName: result.name,
                    rawResult: result.result,
                  ),
                )
                .toList(growable: false),
          );
      if (validationProgressUpdated && _taskReachedTerminalStatus(task.id)) {
        return true;
      }
    }
    if (ConversationPlanExecutionCoordinator.looksLikeVerificationTask(task) &&
        completionAssessment.successfulValidationCommands.isNotEmpty) {
      final validationProgressUpdated = await _conversationsNotifier
          .updateCurrentValidationProgressFromToolResults(
            task: task,
            toolResults: toolResults
                .map(
                  (result) => ConversationValidationToolResultInput(
                    toolName: result.name,
                    rawResult: result.result,
                  ),
                )
                .toList(growable: false),
          );
      if (validationProgressUpdated && _taskReachedTerminalStatus(task.id)) {
        return true;
      }
    }
    if (completionAssessment.hasCompletionEvidenceIgnoringFailures &&
        onlyRecoverableMalformedFailures) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Ignored recoverable malformed tool failures after the saved task had already met its completion evidence.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (!WorkflowToolResultFailureDetector.containsFailure(toolResults) &&
        await _maybeFinalizeScaffoldFromWorkspaceTargets(task: task)) {
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceValidation(
      task: task,
      toolResults: toolResults,
      existingTargetPaths: existingWorkspaceTargets,
    )) {
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: _now(),
        lastValidationCommand:
            completionAssessment.successfulValidationCommands.firstOrNull ??
            task.validationCommand,
        lastValidationSummary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary:
            'Marked complete after the saved validation succeeded and every target file already existed in the workspace.',
      );
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteScaffoldCompletionFromWorkspaceValidation(
      task: task,
      toolResults: toolResults,
      existingTargetPaths: existingWorkspaceTargets,
    )) {
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: _now(),
        lastValidationCommand:
            completionAssessment.successfulValidationCommands.firstOrNull ??
            task.validationCommand,
        lastValidationSummary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary:
            'Marked complete after the saved validation succeeded and every scaffold target file already existed in the workspace.',
      );
      return true;
    }
    if (ConversationPlanExecutionCoordinator.looksLikeVerificationTask(task) &&
        completionAssessment.successfulValidationCommands.isNotEmpty &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        )) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : currentProgress?.normalizedValidationSummary ??
                'Marked complete after the saved verification command succeeded.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (completionAssessment.hasCompletionEvidenceIgnoringFailures &&
        completionAssessment.successfulValidationCommands.isNotEmpty &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        )) {
      final summary =
          currentProgress?.normalizedValidationSummary ??
          currentProgress?.normalizedSummary;
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary == null || summary.isEmpty
            ? 'Marked complete after the saved validation succeeded and the current target files already existed in the workspace.'
            : summary,
      );
      return true;
    }
    if (currentValidationHandoffEvidence) {
      final validationSummary =
          currentProgress?.normalizedValidationSummary ?? '';
      final summary = validationSummary.isNotEmpty
          ? validationSummary
          : 'Marked complete after the saved validation succeeded before the assistant moved on to a later saved task.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (ConversationPlanExecutionGuardrails.canPromoteCompletionFromTaskHandoff(
      task: task,
      toolResults: toolResults,
      assistantResponse: handoffAssistantResponse,
      futureTaskTitles: futureTaskTitles,
    )) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant finished the current saved task and moved on to a later task in the same turn.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (handoffEvidence &&
        ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
          task: task,
          existingTargetPaths: existingWorkspaceTargets,
        ) &&
        (!WorkflowToolResultFailureDetector.containsFailure(toolResults) ||
            onlyUnavailableToolFailures)) {
      final summary =
          assistantInference.status == ConversationWorkflowTaskStatus.completed
          ? assistantInference.summary
          : 'Marked complete after the assistant moved on to a later saved task and every current target file already existed in the workspace.';
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary,
      );
      return true;
    }
    if (historicalValidationHandoffEvidence) {
      final summary =
          currentProgress?.normalizedValidationSummary ??
          currentProgress?.normalizedSummary ??
          assistantInference.summary;
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationAt: _now(),
        lastValidationCommand:
            currentProgress?.normalizedValidationCommand ??
            task.validationCommand,
        lastValidationSummary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
        eventType: ConversationExecutionTaskEventType.completed,
        eventSummary: summary.isEmpty
            ? 'Marked complete after a passed saved validation and a later saved-task handoff.'
            : summary,
      );
      return true;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        completionAssessment.hasCompletionEvidenceIgnoringFailures) {
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: assistantInference.summary,
      );
      return true;
    }
    if (!WorkflowToolResultFailureDetector.containsFailure(toolResults) &&
        completionAssessment.shouldMarkCompleted) {
      final summary = completionAssessment.completedFromSuccessfulValidation
          ? 'Marked complete from saved target file changes and a successful validation result.'
          : completionAssessment.touchedAllTargetFiles &&
                completionAssessment.hasTargetFiles
          ? 'Marked complete after covering every saved target file.'
          : 'Marked complete from saved target file changes.';
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: summary,
      );
      return true;
    }
    if (assistantInference.status == ConversationWorkflowTaskStatus.blocked &&
        recoverableMissingTargetFile == null) {
      await _conversationsNotifier
          .updateCurrentExecutionTaskProgressFromAssistantTurn(
            task: task,
            assistantResponse: latestAssistantResponse,
            isValidationRun: false,
            fallbackAssistantResponse: fallbackAssistantEvidence,
          );
      return true;
    }
    final shouldLockCompletedTaskBeforeNextToolWork =
        assistantInference.status == ConversationWorkflowTaskStatus.completed &&
        !WorkflowToolResultFailureDetector.containsFailure(toolResults) &&
        completionAssessment.touchedTargetFiles.isNotEmpty &&
        completionAssessment.unrelatedTouchedPaths.isNotEmpty;
    if (shouldLockCompletedTaskBeforeNextToolWork) {
      await _markTaskCompletedFromToolEvidence(
        task: task,
        conversationsNotifier: _conversationsNotifier,
        completionAssessment: completionAssessment,
        summary: assistantInference.summary,
      );
      return true;
    }
    if (WorkflowToolResultFailureDetector.containsFailure(toolResults)) {
      return false;
    }
    return false;
  }

  Future<void> _markTaskCompletedFromToolEvidence({
    required ConversationWorkflowTask task,
    required ConversationsNotifier conversationsNotifier,
    required ConversationPlanExecutionCompletionAssessment completionAssessment,
    required String summary,
  }) async {
    final normalizedSummary = summary.trim().isEmpty
        ? 'Marked complete from saved task evidence.'
        : summary.trim();
    final successfulValidationCommand =
        completionAssessment.successfulValidationCommands.firstOrNull;
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: ConversationWorkflowTaskStatus.completed,
      summary: normalizedSummary,
      validationStatus: successfulValidationCommand == null
          ? null
          : ConversationExecutionValidationStatus.passed,
      lastValidationAt: successfulValidationCommand == null ? null : _now(),
      lastValidationCommand:
          successfulValidationCommand ?? task.validationCommand,
      lastValidationSummary: successfulValidationCommand == null
          ? null
          : normalizedSummary,
      eventType: ConversationExecutionTaskEventType.completed,
      eventSummary: normalizedSummary,
    );
  }

  Message? _latestAssistantMessage(Conversation conversation) {
    for (final message in conversation.messages.reversed) {
      if (message.role == MessageRole.assistant &&
          !message.isStreaming &&
          message.content.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  String? _latestAssistantMessageId(Conversation conversation) =>
      _latestAssistantMessage(conversation)?.id;

  List<String> _latestTurnChangedFilePaths() {
    final currentConversation = _readCurrentConversation();
    if (currentConversation == null) {
      return const [];
    }
    final diff = currentConversation.effectiveTurnDiffs.lastOrNull;
    return diff?.changedFilePaths ?? const [];
  }

  bool _taskReachedTerminalStatus(String taskId) {
    if (!_isPageMounted()) {
      return false;
    }
    final currentConversation = _readCurrentConversation();
    final latestTask = currentConversation?.projectedExecutionTasks
        .where((task) => task.id == taskId)
        .firstOrNull;
    return WorkflowTaskRunLifecyclePolicy.isTerminalStatus(latestTask?.status);
  }
}
