import 'dart:convert';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_plan_execution_coordinator.dart';
import 'conversation_plan_hash.dart';
import 'verification_cadence_policy.dart';

enum ExecutionSnapshotAction {
  idle,
  clarify,
  plan,
  execute,
  verify,
  repair,
  complete,
  blocked,
}

class ExecutionSnapshot {
  const ExecutionSnapshot({
    required this.contractHash,
    required this.workflowStage,
    required this.action,
    required this.activeTaskId,
    required this.activeTaskStatus,
    required this.validationStatus,
    required this.completedTaskCount,
    required this.remainingTaskCount,
    required this.unresolvedQuestionCount,
    required this.requiresValidation,
    required this.latestDiagnostic,
    this.objective = '',
    this.constraints = const <String>[],
    this.acceptanceCriteria = const <String>[],
    this.activeTaskTitle = '',
    this.activeTaskTargetFiles = const <String>[],
    this.activeTaskValidationCommand = '',
    this.remainingTaskIds = const <String>[],
    this.clarificationQuestions = const <String>[],
    this.blockingAssumptionCount = 0,
    this.sourceCount = 0,
    this.sourcedItemCount = 0,
    this.mutationGeneration = 0,
    this.verificationGeneration = -1,
    this.verificationCadence = VerificationCadence.notDue,
    this.commandDiagnosticStreak = 0,
    this.commandDiagnosticHasPath = false,
  });

  final String contractHash;
  final ConversationWorkflowStage workflowStage;
  final ExecutionSnapshotAction action;
  final String? activeTaskId;
  final ConversationWorkflowTaskStatus? activeTaskStatus;
  final ConversationExecutionValidationStatus validationStatus;
  final int completedTaskCount;
  final int remainingTaskCount;
  final int unresolvedQuestionCount;
  final bool requiresValidation;
  final String? latestDiagnostic;
  final String objective;
  final List<String> constraints;
  final List<String> acceptanceCriteria;
  final String activeTaskTitle;
  final List<String> activeTaskTargetFiles;
  final String activeTaskValidationCommand;
  final List<String> remainingTaskIds;
  final List<String> clarificationQuestions;
  final int blockingAssumptionCount;
  final int sourceCount;
  final int sourcedItemCount;
  final int mutationGeneration;
  final int verificationGeneration;
  final VerificationCadence verificationCadence;
  final int commandDiagnosticStreak;
  final bool commandDiagnosticHasPath;

  bool get hasContract => contractHash.isNotEmpty;

  String? get activeTaskRef {
    final taskId = activeTaskId?.trim();
    if (taskId == null || taskId.isEmpty) {
      return null;
    }
    return computeConversationPlanHash(taskId);
  }

  String get observationKey => <Object?>[
    contractHash,
    workflowStage.name,
    action.name,
    activeTaskId,
    activeTaskStatus?.name,
    validationStatus.name,
    completedTaskCount,
    remainingTaskCount,
    unresolvedQuestionCount,
    requiresValidation,
    latestDiagnostic,
    commandDiagnosticStreak,
    commandDiagnosticHasPath,
    clarificationQuestions.join('\n'),
  ].join('|');

  bool get hasBlockingAssumptions => blockingAssumptionCount > 0;

  String toPromptContext() {
    final lines = <String>[
      'Contract hash: ${contractHash.isEmpty ? 'none' : contractHash}',
      'Workflow stage: ${workflowStage.name}',
      'Required next action: ${action.name}',
    ];
    if (objective.trim().isNotEmpty) {
      lines.add('Objective: ${_clip(objective, 500)}');
    }
    if (constraints.isNotEmpty) {
      lines.add('Constraints: ${_joined(constraints, 4)}');
    }
    if (acceptanceCriteria.isNotEmpty) {
      lines.add('Acceptance criteria: ${_joined(acceptanceCriteria, 6)}');
    }
    if (activeTaskId != null) {
      lines.add('Active task ID: $activeTaskId');
      if (activeTaskTitle.trim().isNotEmpty) {
        lines.add('Active task: ${_clip(activeTaskTitle, 300)}');
      }
      lines.add('Active task status: ${activeTaskStatus?.name ?? 'unknown'}');
      if (activeTaskTargetFiles.isNotEmpty) {
        lines.add('Target files: ${_joined(activeTaskTargetFiles, 8)}');
      }
      if (activeTaskValidationCommand.trim().isNotEmpty) {
        lines.add(
          'Validation command: ${_clip(activeTaskValidationCommand, 400)}',
        );
      }
    }
    if (remainingTaskIds.isNotEmpty) {
      lines.add('Remaining task IDs: ${remainingTaskIds.take(12).join(', ')}');
    }
    lines.add('Contract sources: $sourceCount');
    lines.add('Sourced contract items: $sourcedItemCount');
    lines.add('Mutation generation: $mutationGeneration');
    lines.add('Verification generation: $verificationGeneration');
    lines.add('Verification cadence: ${verificationCadence.name}');
    if (latestDiagnostic != null) {
      lines.add('Latest failed diagnostic: ${_clip(latestDiagnostic!, 600)}');
    }
    if (commandDiagnosticStreak > 0) {
      final isRepeatedDiagnostic = commandDiagnosticStreak >= 2;
      lines.add(
        isRepeatedDiagnostic
            ? 'Repeated command diagnostic streak: $commandDiagnosticStreak'
            : 'Command diagnostic streak: $commandDiagnosticStreak',
      );
      if (action == ExecutionSnapshotAction.repair) {
        final correctiveAction = commandDiagnosticHasPath
            ? 'make one concrete file mutation'
            : 'take one concrete corrective action';
        if (isRepeatedDiagnostic) {
          lines.add(
            'Repair focus: this diagnostic repeated unchanged. '
            '$correctiveAction that directly addresses it. Do not rerun '
            'unchanged validation again.',
          );
        } else {
          lines.add(
            'Repair focus: inspect the diagnostic context only as needed, '
            'then $correctiveAction that directly addresses it. Do not '
            'rerun unchanged validation before corrective action.',
          );
        }
      }
    }
    if (hasBlockingAssumptions) {
      lines.add(
        'Material assumptions requiring user confirmation: '
        '${_joined(clarificationQuestions, 3)}',
      );
      lines.add(
        'Do not mutate state until the user confirms one of these material assumptions. Ask one focused clarification question.',
      );
    } else if (clarificationQuestions.isNotEmpty) {
      lines.add('Open questions: ${_joined(clarificationQuestions, 3)}');
    }
    return lines.join('\n');
  }

  String _joined(List<String> values, int limit) =>
      _representativeItems(values, limit)
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => _clip(value, 300))
          .join(' | ');

  List<String> _representativeItems(List<String> values, int limit) {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalized.length <= limit) return normalized;
    final headCount = (limit + 1) ~/ 2;
    final tailCount = limit - headCount;
    return <String>[
      ...normalized.take(headCount),
      ...normalized.skip(normalized.length - tailCount),
    ];
  }

  String _clip(String value, int maxLength) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength)}…';
  }

  String toRedactedLogSummary() {
    return <String>[
      'contract=${contractHash.isEmpty ? 'none' : contractHash}',
      'stage=${workflowStage.name}',
      'action=${action.name}',
      'activeTaskRef=${activeTaskRef ?? 'none'}',
      'taskStatus=${activeTaskStatus?.name ?? 'none'}',
      'validation=${validationStatus.name}',
      'tasks=$completedTaskCount/${completedTaskCount + remainingTaskCount}',
      'questions=$unresolvedQuestionCount',
      'requiresValidation=$requiresValidation',
      'hasDiagnostic=${latestDiagnostic != null}',
      'diagnosticStreak=$commandDiagnosticStreak',
    ].join(' ');
  }

  ExecutionSnapshot withCommandDiagnosticRepairFocus({
    required String diagnosticSummary,
    required int streak,
    required bool hasPathBackedDiagnostic,
  }) {
    final preservesBoundary =
        action == ExecutionSnapshotAction.clarify ||
        action == ExecutionSnapshotAction.plan ||
        action == ExecutionSnapshotAction.blocked;
    return ExecutionSnapshot(
      contractHash: contractHash,
      workflowStage: workflowStage,
      action: preservesBoundary ? action : ExecutionSnapshotAction.repair,
      activeTaskId: activeTaskId,
      activeTaskStatus: activeTaskStatus,
      validationStatus: ConversationExecutionValidationStatus.failed,
      completedTaskCount: completedTaskCount,
      remainingTaskCount: remainingTaskCount,
      unresolvedQuestionCount: unresolvedQuestionCount,
      requiresValidation: requiresValidation,
      latestDiagnostic: diagnosticSummary,
      objective: objective,
      constraints: constraints,
      acceptanceCriteria: acceptanceCriteria,
      activeTaskTitle: activeTaskTitle,
      activeTaskTargetFiles: activeTaskTargetFiles,
      activeTaskValidationCommand: activeTaskValidationCommand,
      remainingTaskIds: remainingTaskIds,
      clarificationQuestions: clarificationQuestions,
      blockingAssumptionCount: blockingAssumptionCount,
      sourceCount: sourceCount,
      sourcedItemCount: sourcedItemCount,
      mutationGeneration: mutationGeneration,
      verificationGeneration: verificationGeneration,
      verificationCadence: verificationCadence,
      commandDiagnosticStreak: streak,
      commandDiagnosticHasPath: hasPathBackedDiagnostic,
    );
  }
}

class ExecutionSnapshotProjector {
  const ExecutionSnapshotProjector();

  /// Derives the verification cadence for a conversation.
  ///
  /// Callers that need only the cadence must use this rather than reading it
  /// off [project]: `project` returns early for a conversation with no
  /// workflow context and yields the [ExecutionSnapshot] default `notDue`,
  /// which is indistinguishable from "computed, and not due". The cadence
  /// itself is conversation-level — it depends on the mutation and
  /// verification generations, not on whether a plan exists — so it is
  /// meaningful even when the snapshot is empty.
  static VerificationCadence verificationCadenceFor(Conversation conversation) {
    final activeTask = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    final progress = activeTask == null
        ? null
        : conversation.executionProgressForTask(activeTask.id);
    final validationStatus =
        progress?.validationStatus ??
        ConversationExecutionValidationStatus.unknown;
    return const VerificationCadencePolicy().decide(
      mutationGeneration: conversation.mutationGeneration,
      verificationGeneration: conversation.verificationGeneration,
      taskRequiresValidation:
          activeTask?.validationCommand.trim().isNotEmpty ?? false,
      taskCompleted:
          activeTask?.status == ConversationWorkflowTaskStatus.completed,
      validationFailed:
          validationStatus == ConversationExecutionValidationStatus.failed,
    );
  }

  ExecutionSnapshot project(Conversation? conversation) {
    if (conversation == null || !conversation.hasWorkflowContext) {
      return const ExecutionSnapshot(
        contractHash: '',
        workflowStage: ConversationWorkflowStage.idle,
        action: ExecutionSnapshotAction.idle,
        activeTaskId: null,
        activeTaskStatus: null,
        validationStatus: ConversationExecutionValidationStatus.unknown,
        completedTaskCount: 0,
        remainingTaskCount: 0,
        unresolvedQuestionCount: 0,
        requiresValidation: false,
        latestDiagnostic: null,
      );
    }

    final tasks = conversation.projectedExecutionTasks;
    final activeTask = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    final progress = activeTask == null
        ? null
        : conversation.executionProgressForTask(activeTask.id);
    final blockingAssumptions =
        conversation.effectiveWorkflowSpec.blockingAssumptions;
    final clarificationQuestions = <String>{
      ...conversation.unresolvedOpenQuestionProgress.map(
        (item) => item.question.trim(),
      ),
      ...blockingAssumptions.map(
        (item) =>
            item.normalizedClarificationQuestion ??
            'Confirm the material ${item.kind.name} assumption.',
      ),
    }.where((item) => item.isNotEmpty).toList(growable: false);
    final completedTaskCount = tasks
        .where(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final remainingTaskCount = tasks.length - completedTaskCount;
    final validationStatus =
        progress?.validationStatus ??
        ConversationExecutionValidationStatus.unknown;
    final requiresValidation =
        activeTask?.validationCommand.trim().isNotEmpty ?? false;
    final latestDiagnostic = _latestDiagnostic(progress);
    final verificationCadence = verificationCadenceFor(conversation);

    return ExecutionSnapshot(
      contractHash: _contractHash(conversation.effectiveWorkflowSpec),
      workflowStage: conversation.workflowStage,
      action: _actionFor(
        workflowStage: conversation.workflowStage,
        tasks: tasks,
        activeTask: activeTask,
        progress: progress,
        unresolvedQuestionCount: clarificationQuestions.length,
        verificationCadence: verificationCadence,
      ),
      activeTaskId: activeTask?.id,
      activeTaskStatus: activeTask?.status,
      validationStatus: validationStatus,
      completedTaskCount: completedTaskCount,
      remainingTaskCount: remainingTaskCount,
      unresolvedQuestionCount: clarificationQuestions.length,
      requiresValidation: requiresValidation,
      latestDiagnostic: latestDiagnostic,
      objective: conversation.effectiveWorkflowSpec.goal,
      constraints: conversation.effectiveWorkflowSpec.constraints,
      acceptanceCriteria: conversation.effectiveWorkflowSpec.acceptanceCriteria,
      activeTaskTitle: activeTask?.title ?? '',
      activeTaskTargetFiles: activeTask?.targetFiles ?? const <String>[],
      activeTaskValidationCommand: activeTask?.validationCommand ?? '',
      remainingTaskIds: tasks
          .where(
            (task) => task.status != ConversationWorkflowTaskStatus.completed,
          )
          .map((task) => task.id)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      clarificationQuestions: clarificationQuestions,
      blockingAssumptionCount: blockingAssumptions.length,
      sourceCount: conversation.effectiveWorkflowSpec.sources.length,
      sourcedItemCount: conversation.effectiveWorkflowSpec.provenance
          .where((item) => item.sourceIds.isNotEmpty)
          .length,
      mutationGeneration: conversation.mutationGeneration,
      verificationGeneration: conversation.verificationGeneration,
      verificationCadence: verificationCadence,
    );
  }

  ExecutionSnapshotAction _actionFor({
    required ConversationWorkflowStage workflowStage,
    required List<ConversationWorkflowTask> tasks,
    required ConversationWorkflowTask? activeTask,
    required ConversationExecutionTaskProgress? progress,
    required int unresolvedQuestionCount,
    required VerificationCadence verificationCadence,
  }) {
    if (unresolvedQuestionCount > 0) {
      return ExecutionSnapshotAction.clarify;
    }
    if (activeTask?.status == ConversationWorkflowTaskStatus.blocked ||
        progress?.status == ConversationWorkflowTaskStatus.blocked) {
      return ExecutionSnapshotAction.blocked;
    }
    if (workflowStage == ConversationWorkflowStage.plan) {
      return ExecutionSnapshotAction.plan;
    }
    if (progress?.validationStatus ==
        ConversationExecutionValidationStatus.failed) {
      return ExecutionSnapshotAction.repair;
    }
    if (verificationCadence == VerificationCadence.required) {
      return ExecutionSnapshotAction.verify;
    }
    if (tasks.isNotEmpty &&
        tasks.every(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        )) {
      return ExecutionSnapshotAction.complete;
    }
    if (activeTask == null) {
      return ExecutionSnapshotAction.idle;
    }
    if (ConversationPlanExecutionCoordinator.looksLikeVerificationTask(
          activeTask,
        ) ||
        (activeTask.status == ConversationWorkflowTaskStatus.inProgress &&
            activeTask.validationCommand.trim().isNotEmpty &&
            progress?.lastRunAt != null)) {
      return ExecutionSnapshotAction.verify;
    }
    return ExecutionSnapshotAction.execute;
  }

  String? _latestDiagnostic(ConversationExecutionTaskProgress? progress) {
    if (progress == null) {
      return null;
    }
    if (progress.validationStatus ==
        ConversationExecutionValidationStatus.failed) {
      return progress.normalizedValidationSummary ?? progress.normalizedSummary;
    }
    if (progress.status == ConversationWorkflowTaskStatus.blocked) {
      return progress.normalizedBlockedReason ?? progress.normalizedSummary;
    }
    for (final event in progress.recentEvents.reversed) {
      final isFailure =
          event.validationStatus ==
              ConversationExecutionValidationStatus.failed ||
          event.status == ConversationWorkflowTaskStatus.blocked;
      if (!isFailure) {
        continue;
      }
      final summary =
          event.normalizedValidationSummary ??
          event.normalizedBlockedReason ??
          event.normalizedSummary;
      if (summary != null) {
        return summary;
      }
    }
    return null;
  }

  String _contractHash(ConversationWorkflowSpec spec) {
    if (!spec.hasContent) {
      return '';
    }
    final canonical = jsonEncode(<String, Object>{
      'goal': spec.goal.trim(),
      'constraints': _normalizedItems(spec.constraints),
      'acceptanceCriteria': _normalizedItems(spec.acceptanceCriteria),
      'openQuestions': _normalizedItems(spec.openQuestions),
      'tasks': spec.tasks
          .map(
            (task) => <String, Object>{
              'id': task.id.trim(),
              'title': task.title.trim(),
              'targetFiles': _normalizedItems(task.targetFiles),
              'validationCommand': task.validationCommand.trim(),
              'notes': task.notes.trim(),
            },
          )
          .toList(growable: false),
      'sources': spec.sources
          .map(
            (source) => <String, Object>{
              'id': source.id,
              'kind': source.kind.name,
              'contentHash': source.contentHash,
            },
          )
          .toList(growable: false),
      'provenance': spec.provenance
          .map(
            (item) => <String, Object>{
              'itemId': item.itemId,
              'kind': item.kind.name,
              'sourceIds': item.sourceIds,
              'assumption': item.assumption,
              'material': item.material,
              'confirmed': item.confirmed,
            },
          )
          .toList(growable: false),
    });
    return computeConversationPlanHash(canonical);
  }

  List<String> _normalizedItems(List<String> items) => items
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
