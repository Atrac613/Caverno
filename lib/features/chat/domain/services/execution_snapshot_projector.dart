import 'dart:convert';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_contract_provenance_service.dart';
import 'conversation_plan_execution_coordinator.dart';
import 'conversation_plan_hash.dart';
import 'conversation_task_readiness.dart';
import 'task_delegation_brief_builder.dart';
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
    this.blockingAssumptions = const <String>[],
    this.waitingTasks = const <String>[],
    this.delegatableTasks = const <String>[],
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

  /// The claims the plan is assuming and the user has not confirmed, in the
  /// plan's own words.
  ///
  /// ANA0 PR 5. This used to be a count beside `clarificationQuestions`, and
  /// the prompt rendered *that* list under the heading "material assumptions
  /// requiring user confirmation" — a set unioning open questions with
  /// assumption questions, sampled head-and-tail to three. So the line could
  /// name three open questions and omit the assumption that was actually
  /// blocking the turn, while claiming to list it. Carrying the claims
  /// themselves is what makes the line true.
  final List<String> blockingAssumptions;

  /// Tasks whose preconditions do not hold yet, each with what it waits on.
  ///
  /// ANA1 derives readiness and renders it in the task card; this is the same
  /// fact reaching the model. Without it the prompt lists a task as remaining
  /// and says nothing about the edge holding it, so the model's only options
  /// are to start work that cannot be finished or to guess why it should not.
  final List<String> waitingTasks;

  /// Tasks that could be handed to a child right now, with their premises and
  /// runner.
  ///
  /// Carried on the snapshot but deliberately **not** in [toPromptContext]:
  /// this is what the Anabasis parent orchestrates with, and
  /// `SystemPromptBuilder` emits it only for a turn addressed to the parent.
  /// An ordinary turn has no use for a delegation queue and would read it as a
  /// suggestion to spawn children.
  final List<String> delegatableTasks;
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

  int get blockingAssumptionCount => blockingAssumptions.length;

  bool get hasBlockingAssumptions => blockingAssumptions.isNotEmpty;

  String toPromptContext() {
    final lines = <String>[
      'Contract hash: ${contractHash.isEmpty ? 'none' : contractHash}',
      'Workflow stage: ${workflowStage.name}',
      'Required next action: ${action.name}',
    ];
    final totalTaskCount = completedTaskCount + remainingTaskCount;
    if (totalTaskCount > 0) {
      // The saved-task list further down the prompt carries each task's
      // authored status, which nothing writes completion back to. Without this
      // line the model's only view of progress was that stale list, so a fully
      // executed plan still read as five pending tasks (session a0ca65b7).
      lines.add(
        'Saved task progress: $completedTaskCount of $totalTaskCount '
        'completed',
      );
      if (remainingTaskCount == 0) {
        lines.add(
          'Every saved task is complete. Do not re-inspect completed task '
          'files to look for remaining work; report the outcome or take the '
          'next step the user asked for.',
        );
      }
    }
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
        'Unconfirmed material assumptions: ${_joined(blockingAssumptions, 3)}',
      );
      // Caverno raises the confirmation itself when a mutation is attempted
      // (ANA0 PR 4b-2), so this states what is true rather than delegating the
      // mechanism: asking the model to ask was the humility instruction the
      // track exists to replace.
      lines.add(
        'State mutation is blocked until the user confirms one of these. They '
        'are asked when a mutation is attempted; treat the assumption as open '
        'until then, and do not write it into the plan as established.',
      );
    }
    if (clarificationQuestions.isNotEmpty) {
      lines.add('Open questions: ${_joined(clarificationQuestions, 3)}');
    }
    if (waitingTasks.isNotEmpty) {
      lines.add('Tasks not ready: ${_joined(waitingTasks, 3)}');
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
      'assumptions=$blockingAssumptionCount',
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
      blockingAssumptions: blockingAssumptions,
      waitingTasks: waitingTasks,
      delegatableTasks: delegatableTasks,
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

    final taskViews = conversation.executionTaskViews;
    final activeTask = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    final progress = activeTask == null
        ? null
        : conversation.executionProgressForTask(activeTask.id);
    final spec = conversation.effectiveWorkflowSpec;
    const provenance = ConversationContractProvenanceService();
    // The claim, not the question about it: the prompt says what is being
    // assumed, and the app is what asks. Falling back to the question keeps a
    // hand-marked item that no longer matches any list from disappearing
    // silently.
    final blockingAssumptionClaims = spec.blockingAssumptions
        .map(
          (item) =>
              provenance.itemValueFor(spec, item.itemId) ??
              item.normalizedClarificationQuestion ??
              'An unnamed material ${item.kind.name} assumption',
        )
        .where((claim) => claim.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    // What each unready task waits on, in the plan's own words where it has
    // them. The reference is rendered rather than the item id, because an id is
    // a hash and a prompt line naming one tells the model nothing it can act
    // on.
    const readiness = ConversationTaskReadinessResolver();
    final waitingTaskSummaries = <String>[
      for (final task in spec.tasks)
        if (task.title.trim().isNotEmpty)
          if (readiness.resolve(conversation, task).unmet case final unmet
              when unmet.isNotEmpty)
            '${task.title.trim()} — waits on '
                '${unmet.map((edge) => '${edge.kind.name}: '
                    '${provenance.itemValueFor(spec, edge.ref) ?? edge.ref}').join('; ')}',
    ];
    // What the parent could delegate now, with the premises a child would have
    // to be told and the runner the work's own declarations put it in.
    final delegatableSummaries = <String>[
      for (final brief in const TaskDelegationBriefBuilder().candidates(
        conversation,
      ))
        [
          brief.task.title.trim(),
          '(${brief.runner.name})',
          if (brief.premises.isNotEmpty)
            '— premises: ${brief.premises.join('; ')}',
        ].join(' '),
    ];
    // Open questions only. Unioning the assumption questions in here is what
    // let the material-assumption line render three open questions and omit
    // the assumption that was blocking the turn.
    final clarificationQuestions = conversation.unresolvedOpenQuestionProgress
        .map((item) => item.question.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final completedTaskCount = taskViews
        .where(
          (view) => view.status == ConversationWorkflowTaskStatus.completed,
        )
        .length;
    final remainingTaskCount = taskViews.length - completedTaskCount;
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
        taskViews: taskViews,
        activeTask: activeTask,
        progress: progress,
        unresolvedQuestionCount: clarificationQuestions.length,
        blockingAssumptionCount: blockingAssumptionClaims.length,
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
      remainingTaskIds: taskViews
          .where(
            (view) => view.status != ConversationWorkflowTaskStatus.completed,
          )
          .map((view) => view.task.id)
          .where((id) => id.trim().isNotEmpty)
          .toList(growable: false),
      clarificationQuestions: clarificationQuestions,
      blockingAssumptions: blockingAssumptionClaims,
      waitingTasks: waitingTaskSummaries,
      delegatableTasks: delegatableSummaries,
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
    required List<ExecutionTaskView> taskViews,
    required ConversationWorkflowTask? activeTask,
    required ConversationExecutionTaskProgress? progress,
    required int unresolvedQuestionCount,
    required int blockingAssumptionCount,
    required VerificationCadence verificationCadence,
  }) {
    // Both, named separately. They used to arrive as one conflated count, and
    // splitting the lists (ANA0 PR 5) silently turned a contract blocked on an
    // assumption into `execute` — the sort of change a projection makes when a
    // count is asked to mean two things.
    if (unresolvedQuestionCount > 0 || blockingAssumptionCount > 0) {
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
    if (taskViews.isNotEmpty &&
        taskViews.every(
          (view) => view.status == ConversationWorkflowTaskStatus.completed,
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
