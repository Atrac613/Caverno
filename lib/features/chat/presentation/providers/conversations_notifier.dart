import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/conversation_execution_progress_inference.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../../domain/services/conversation_validation_tool_result_inference.dart';

/// State for the conversation list.
class ConversationsState {
  const ConversationsState({
    required this.conversations,
    required this.currentConversationId,
    required this.activeWorkspaceMode,
    required this.activeProjectId,
    this.isLoading = false,
  });

  final List<Conversation> conversations;
  final String? currentConversationId;
  final WorkspaceMode activeWorkspaceMode;
  final String? activeProjectId;
  final bool isLoading;

  factory ConversationsState.initial() => const ConversationsState(
    conversations: [],
    currentConversationId: null,
    activeWorkspaceMode: WorkspaceMode.chat,
    activeProjectId: null,
  );

  ConversationsState copyWith({
    List<Conversation>? conversations,
    String? currentConversationId,
    WorkspaceMode? activeWorkspaceMode,
    String? activeProjectId,
    bool? isLoading,
    bool clearCurrentConversation = false,
    bool clearActiveProject = false,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      currentConversationId: clearCurrentConversation
          ? null
          : (currentConversationId ?? this.currentConversationId),
      activeWorkspaceMode: activeWorkspaceMode ?? this.activeWorkspaceMode,
      activeProjectId: clearActiveProject
          ? null
          : (activeProjectId ?? this.activeProjectId),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Returns the currently selected conversation.
  Conversation? get currentConversation {
    if (currentConversationId == null) return null;
    try {
      return conversations.firstWhere((c) => c.id == currentConversationId);
    } catch (_) {
      return null;
    }
  }

  List<Conversation> get visibleConversations {
    return conversations
        .where((conversation) {
          if (conversation.workspaceMode != activeWorkspaceMode) {
            return false;
          }
          if (activeWorkspaceMode == WorkspaceMode.chat) {
            return true;
          }
          return conversation.normalizedProjectId == activeProjectId;
        })
        .toList(growable: false);
  }
}

/// Provider for `ConversationsNotifier`.
final conversationsNotifierProvider =
    NotifierProvider<ConversationsNotifier, ConversationsState>(
      ConversationsNotifier.new,
    );

/// Default title for new conversations (used as a sentinel for auto-title).
const defaultConversationTitle = '__new_conversation__';

/// Notifier that manages the conversation list.
class ConversationsNotifier extends Notifier<ConversationsState> {
  late final ConversationRepository _repository;
  final _uuid = const Uuid();

  @override
  ConversationsState build() {
    _repository = ref.read(conversationRepositoryProvider);
    final scopedState = _buildScopedState(
      conversations: _repository.getAll(),
      workspaceMode: WorkspaceMode.chat,
      projectId: null,
      createIfMissing: true,
    );
    Future<void>.microtask(() async {
      if (!ref.mounted) {
        return;
      }
      await ensureCurrentPlanArtifactBackfilled();
    });
    return scopedState;
  }

  ConversationsState _buildScopedState({
    required List<Conversation> conversations,
    required WorkspaceMode workspaceMode,
    required String? projectId,
    String? preferredConversationId,
    required bool createIfMissing,
  }) {
    final normalizedProjectId = workspaceMode == WorkspaceMode.coding
        ? projectId
        : null;
    final visibleConversations = conversations
        .where((conversation) {
          if (conversation.workspaceMode != workspaceMode) {
            return false;
          }
          if (workspaceMode == WorkspaceMode.chat) {
            return true;
          }
          return conversation.normalizedProjectId == normalizedProjectId;
        })
        .toList(growable: false);

    String? currentConversationId = preferredConversationId;
    if (currentConversationId != null &&
        !visibleConversations.any(
          (conversation) => conversation.id == currentConversationId,
        )) {
      currentConversationId = null;
    }
    currentConversationId ??= visibleConversations.isEmpty
        ? null
        : visibleConversations.first.id;

    var nextConversations = conversations;
    if (currentConversationId == null && createIfMissing) {
      final fresh = _createConversation(
        workspaceMode: workspaceMode,
        projectId: normalizedProjectId,
      );
      _repository.save(fresh);
      nextConversations = [fresh, ...conversations];
      _sortConversations(nextConversations);
      currentConversationId = fresh.id;
    }

    return ConversationsState(
      conversations: nextConversations,
      currentConversationId: currentConversationId,
      activeWorkspaceMode: workspaceMode,
      activeProjectId: normalizedProjectId,
    );
  }

  Conversation _createConversation({
    required WorkspaceMode workspaceMode,
    required String? projectId,
  }) {
    final now = DateTime.now();
    return Conversation(
      id: _uuid.v4(),
      title: defaultConversationTitle,
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: workspaceMode,
      projectId: projectId ?? '',
    );
  }

  void _sortConversations(List<Conversation> conversations) {
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _persistUpdatedConversation(
    Conversation updatedConversation,
  ) async {
    await _repository.save(updatedConversation);

    final newConversations = state.conversations.map((conversation) {
      if (conversation.id == updatedConversation.id) {
        return updatedConversation;
      }
      return conversation;
    }).toList();

    _sortConversations(newConversations);
    state = state.copyWith(conversations: newConversations);
  }

  /// Creates a new conversation.
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    final resolvedProjectId = resolvedWorkspaceMode == WorkspaceMode.coding
        ? (projectId ?? state.activeProjectId)
        : null;
    final conversation = _createConversation(
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId,
    );

    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          resolvedWorkspaceMode == WorkspaceMode.chat ||
          resolvedProjectId == null,
    );

    // Persist the new conversation.
    _repository.save(conversation);
  }

  /// Selects a conversation.
  void selectConversation(String id) {
    final conversation = state.conversations
        .where((item) => item.id == id)
        .firstOrNull;
    if (conversation == null) return;

    state = state.copyWith(
      currentConversationId: id,
      activeWorkspaceMode: conversation.workspaceMode,
      activeProjectId: conversation.normalizedProjectId,
      clearActiveProject: conversation.workspaceMode == WorkspaceMode.chat,
    );
    ensureCurrentPlanArtifactBackfilled();
  }

  void activateWorkspace({
    required WorkspaceMode workspaceMode,
    String? projectId,
    bool createIfMissing = true,
  }) {
    state = _buildScopedState(
      conversations: state.conversations,
      workspaceMode: workspaceMode,
      projectId: projectId,
      preferredConversationId: state.currentConversationId,
      createIfMissing: createIfMissing,
    );
    ensureCurrentPlanArtifactBackfilled();
  }

  /// Deletes a conversation.
  Future<void> deleteConversation(String id) async {
    await _repository.delete(id);

    final newConversations = state.conversations
        .where((c) => c.id != id)
        .toList();
    state = _buildScopedState(
      conversations: newConversations,
      workspaceMode: state.activeWorkspaceMode,
      projectId: state.activeProjectId,
      preferredConversationId: state.currentConversationId == id
          ? null
          : state.currentConversationId,
      createIfMissing:
          state.activeWorkspaceMode == WorkspaceMode.chat ||
          state.activeProjectId != null,
    );
  }

  /// Deletes all conversations in the active scope.
  Future<void> deleteScopedConversations() async {
    final visibleConversationIds = state.visibleConversations
        .map((conversation) => conversation.id)
        .toList(growable: false);
    for (final id in visibleConversationIds) {
      await _repository.delete(id);
    }

    final newConversations = state.conversations
        .where(
          (conversation) => !visibleConversationIds.contains(conversation.id),
        )
        .toList();

    state = _buildScopedState(
      conversations: newConversations,
      workspaceMode: state.activeWorkspaceMode,
      projectId: state.activeProjectId,
      createIfMissing:
          state.activeWorkspaceMode == WorkspaceMode.chat ||
          state.activeProjectId != null,
    );
  }

  Future<void> deleteConversationsForProject(String projectId) async {
    final targetIds = state.conversations
        .where(
          (conversation) =>
              conversation.workspaceMode == WorkspaceMode.coding &&
              conversation.normalizedProjectId == projectId,
        )
        .map((conversation) => conversation.id)
        .toList(growable: false);
    for (final id in targetIds) {
      await _repository.delete(id);
    }

    state = state.copyWith(
      conversations: state.conversations
          .where((conversation) => !targetIds.contains(conversation.id))
          .toList(),
      clearCurrentConversation: targetIds.contains(state.currentConversationId),
    );
  }

  /// Updates messages for the current conversation.
  Future<void> updateCurrentConversation(List<Message> messages) async {
    if (state.currentConversationId == null) return;

    final conversation = state.currentConversation;
    if (conversation == null) return;

    String title = conversation.title;
    if (title == defaultConversationTitle && messages.isNotEmpty) {
      title = _deriveDefaultTitle(messages) ?? title;
    }

    final compactionArtifact = _buildCompactionArtifact(
      conversation,
      messages: messages,
      now: DateTime.now(),
    );
    final updatedConversation = conversation.copyWith(
      title: title,
      messages: messages,
      compactionArtifact: compactionArtifact,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  String? _deriveDefaultTitle(List<Message> messages) {
    for (final message in messages) {
      if (message.role != MessageRole.user) continue;

      final trimmed = message.content.trim();
      if (trimmed.isEmpty) continue;

      return trimmed.length > 30 ? '${trimmed.substring(0, 30)}...' : trimmed;
    }

    return null;
  }

  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) return;

    final nextStage = workflowStage ?? conversation.workflowStage;
    final requestedWorkflowSpec = clearWorkflowSpec
        ? null
        : (workflowSpec ?? conversation.workflowSpec);
    final shouldPreserveProjectedTasks =
        preserveWorkflowProjection &&
        conversation.shouldPreferPlanDocument &&
        conversation.projectedExecutionTasks.isNotEmpty &&
        (requestedWorkflowSpec == null ||
            !requestedWorkflowSpec.hasContent ||
            requestedWorkflowSpec.tasks.isEmpty);
    final nextWorkflowSpec = shouldPreserveProjectedTasks
        ? conversation.workflowSpec
        : requestedWorkflowSpec;

    final updatedConversation = conversation.copyWith(
      workflowStage: nextStage,
      workflowSpec: nextWorkflowSpec,
      workflowSourceHash: preserveWorkflowProjection
          ? (workflowSourceHash ?? conversation.workflowSourceHash)
          : '',
      workflowDerivedAt: preserveWorkflowProjection
          ? (workflowDerivedAt ?? conversation.workflowDerivedAt)
          : null,
      updatedAt: DateTime.now(),
    );

    await _persistUpdatedConversation(updatedConversation);
    await ensureCurrentPlanArtifactBackfilled();
  }

  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) return;

    final nextPlanArtifact = clearPlanArtifact
        ? null
        : (planArtifact?.hasContent ?? false)
        ? planArtifact
        : null;

    final updatedConversation = conversation.copyWith(
      planArtifact: nextPlanArtifact,
      compactionArtifact: _buildCompactionArtifact(
        conversation,
        planArtifact: nextPlanArtifact,
        now: DateTime.now(),
      ),
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> updateCurrentExecutionTaskProgress({
    required String taskId,
    required ConversationWorkflowTaskStatus status,
    bool allowStatusRegression = false,
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? summary,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
    String? eventSummary,
    DateTime? eventTimestamp,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final progress = [...conversation.effectiveExecutionProgress];
    final index = progress.indexWhere(
      (entry) => entry.taskId == normalizedTaskId,
    );
    final previous = index >= 0 ? progress[index] : null;
    final preservesLockedCompletion =
        !allowStatusRegression &&
        _hasLockedTerminalCompletion(previous) &&
        status != ConversationWorkflowTaskStatus.completed;
    final lockedPrevious = preservesLockedCompletion ? previous : null;
    final nextStatus = lockedPrevious?.status ?? status;
    final nextValidationStatus =
        lockedPrevious?.validationStatus ??
        validationStatus ??
        previous?.validationStatus ??
        ConversationExecutionValidationStatus.unknown;
    final nextSummary =
        lockedPrevious?.summary ?? summary?.trim() ?? previous?.summary ?? '';
    final nextBlockedReason = preservesLockedCompletion
        ? ''
        : blockedReason?.trim() ?? previous?.blockedReason ?? '';
    final nextValidationCommand =
        lockedPrevious?.lastValidationCommand ??
        lastValidationCommand?.trim() ??
        previous?.lastValidationCommand ??
        '';
    final nextValidationSummary =
        lockedPrevious?.lastValidationSummary ??
        lastValidationSummary?.trim() ??
        previous?.lastValidationSummary ??
        '';
    final nextEntry = ConversationExecutionTaskProgress(
      taskId: normalizedTaskId,
      status: nextStatus,
      validationStatus: nextValidationStatus,
      updatedAt: now,
      lastRunAt: lastRunAt ?? previous?.lastRunAt,
      lastValidationAt: lastValidationAt ?? previous?.lastValidationAt,
      summary: nextSummary,
      blockedReason: nextBlockedReason,
      lastValidationCommand: nextValidationCommand,
      lastValidationSummary: nextValidationSummary,
      events: _appendExecutionEvent(
        previous?.events ?? const [],
        eventType: preservesLockedCompletion ? null : eventType,
        eventTimestamp: eventTimestamp ?? now,
        status: nextStatus,
        validationStatus: nextValidationStatus,
        summary: preservesLockedCompletion
            ? nextSummary
            : eventSummary?.trim() ?? nextSummary,
        blockedReason: nextBlockedReason,
        validationCommand: nextValidationCommand,
        validationSummary: nextValidationSummary,
      ),
    );

    if (!nextEntry.hasMeaningfulState) {
      if (index >= 0) {
        progress.removeAt(index);
      }
    } else if (index >= 0) {
      progress[index] = nextEntry;
    } else {
      progress.add(nextEntry);
    }

    final updatedConversation = conversation.copyWith(
      executionProgress: progress,
      updatedAt: now,
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> updateCurrentExecutionTaskProgressFromAssistantTurn({
    required ConversationWorkflowTask task,
    required String assistantResponse,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final inference = ConversationExecutionProgressInference.infer(
      assistantResponse: assistantResponse,
      task: task,
      isValidationRun: isValidationRun,
      fallbackAssistantResponse: fallbackAssistantResponse,
    );

    await updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: inference.status,
      summary: inference.summary,
      blockedReason: inference.status == ConversationWorkflowTaskStatus.blocked
          ? inference.blockedReason
          : '',
      validationStatus: isValidationRun ? inference.validationStatus : null,
      lastValidationAt: isValidationRun ? DateTime.now() : null,
      lastValidationCommand: isValidationRun ? task.validationCommand : null,
      lastValidationSummary: isValidationRun
          ? inference.validationSummary ?? inference.summary
          : null,
      eventType: isValidationRun
          ? ConversationExecutionTaskEventType.validated
          : switch (inference.status) {
              ConversationWorkflowTaskStatus.completed =>
                ConversationExecutionTaskEventType.completed,
              ConversationWorkflowTaskStatus.blocked =>
                ConversationExecutionTaskEventType.blocked,
              _ => null,
            },
      eventSummary: inference.summary,
    );

    final refreshedConversation = state.currentConversation;
    final storedStatus =
        refreshedConversation?.executionProgressForTask(task.id)?.status ??
        inference.status;

    if (!conversation.shouldPreferPlanDocument) {
      return;
    }

    if (storedStatus == ConversationWorkflowTaskStatus.completed) {
      await updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.review,
        preserveWorkflowProjection: true,
      );
      return;
    }

    if (storedStatus == ConversationWorkflowTaskStatus.inProgress ||
        storedStatus == ConversationWorkflowTaskStatus.blocked) {
      await updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        preserveWorkflowProjection: true,
      );
    }
  }

  Future<bool> updateCurrentValidationProgressFromToolResults({
    required ConversationWorkflowTask task,
    required Iterable<ConversationValidationToolResultInput> toolResults,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return false;
    }

    final inference = ConversationValidationToolResultInference.infer(
      task: task,
      toolResults: toolResults,
    );
    if (inference == null) {
      return false;
    }

    final previousProgress = conversation.executionProgressForTask(task.id);
    final preservesCompletedValidation =
        previousProgress?.status == ConversationWorkflowTaskStatus.completed &&
        inference.validationStatus ==
            ConversationExecutionValidationStatus.passed &&
        inference.status != ConversationWorkflowTaskStatus.blocked;

    await updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: preservesCompletedValidation
          ? ConversationWorkflowTaskStatus.completed
          : inference.status,
      allowStatusRegression: !preservesCompletedValidation,
      summary: inference.summary,
      blockedReason: inference.status == ConversationWorkflowTaskStatus.blocked
          ? inference.blockedReason ?? ''
          : '',
      validationStatus: inference.validationStatus,
      lastValidationAt: DateTime.now(),
      lastValidationCommand: inference.validationCommand,
      lastValidationSummary: inference.validationSummary,
      eventType: ConversationExecutionTaskEventType.validated,
      eventSummary: inference.summary,
    );

    if (!conversation.shouldPreferPlanDocument) {
      return true;
    }

    if (inference.status == ConversationWorkflowTaskStatus.completed) {
      await updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.review,
        preserveWorkflowProjection: true,
      );
      return true;
    }

    await updateCurrentWorkflow(
      workflowStage: ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
    );
    return true;
  }

  bool _hasLockedTerminalCompletion(
    ConversationExecutionTaskProgress? progress,
  ) {
    if (progress == null ||
        progress.status != ConversationWorkflowTaskStatus.completed) {
      return false;
    }
    if (progress.validationStatus == ConversationExecutionValidationStatus.passed) {
      return true;
    }
    return progress.recentEvents.any(
      (event) => event.type == ConversationExecutionTaskEventType.completed,
    );
  }

  Future<void> retainExecutionTaskProgress(Set<String> taskIds) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final normalizedTaskIds = taskIds
        .map((taskId) => taskId.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    final retained = conversation.effectiveExecutionProgress
        .where((entry) => normalizedTaskIds.contains(entry.taskId))
        .toList(growable: false);

    if (retained.length == conversation.effectiveExecutionProgress.length) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      executionProgress: retained,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> appendCurrentExecutionTaskEvent({
    required String taskId,
    required ConversationExecutionTaskEventType eventType,
    String? summary,
    DateTime? createdAt,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final progress = conversation.executionProgressForTask(taskId);
    final projectedTask = conversation.projectedExecutionTasks
        .where((task) => task.id == taskId)
        .firstOrNull;

    await updateCurrentExecutionTaskProgress(
      taskId: taskId,
      status:
          progress?.status ??
          projectedTask?.status ??
          ConversationWorkflowTaskStatus.pending,
      validationStatus: progress?.validationStatus,
      summary: progress?.summary,
      blockedReason: progress?.blockedReason,
      lastValidationCommand: progress?.lastValidationCommand,
      lastValidationSummary: progress?.lastValidationSummary,
      eventType: eventType,
      eventSummary: summary,
      eventTimestamp: createdAt,
    );
  }

  Future<void> updateCurrentOpenQuestionProgress({
    required String question,
    required ConversationOpenQuestionStatus status,
    String? note,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      return;
    }

    final questionId = Conversation.openQuestionIdFor(normalizedQuestion);
    final progress = [...conversation.effectiveOpenQuestionProgress];
    final index = progress.indexWhere(
      (entry) => entry.questionId == questionId,
    );
    final nextEntry = ConversationOpenQuestionProgress(
      questionId: questionId,
      question: normalizedQuestion,
      status: status,
      note: note?.trim() ?? (index >= 0 ? progress[index].note : ''),
      updatedAt: DateTime.now(),
    );

    if (index >= 0) {
      progress[index] = nextEntry;
    } else {
      progress.add(nextEntry);
    }

    final updatedConversation = conversation.copyWith(
      openQuestionProgress: progress,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> retainOpenQuestionProgress(Iterable<String> questions) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final retainedQuestionIds = questions
        .map(Conversation.openQuestionIdFor)
        .where((questionId) => questionId.isNotEmpty)
        .toSet();
    final retained = conversation.effectiveOpenQuestionProgress
        .where((entry) => retainedQuestionIds.contains(entry.questionId))
        .toList(growable: false);

    if (retained.length == conversation.effectiveOpenQuestionProgress.length) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      openQuestionProgress: retained,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> ensureCurrentPlanArtifactBackfilled() async {
    final conversation = state.currentConversation;
    if (conversation == null ||
        conversation.hasPlanArtifact ||
        !conversation.hasWorkflowContext) {
      return;
    }

    final planArtifact = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: conversation.workflowStage,
      workflowSpec: conversation.effectiveWorkflowSpec,
      updatedAt: DateTime.now(),
    );
    final updatedConversation = conversation.copyWith(
      planArtifact: planArtifact,
      compactionArtifact: _buildCompactionArtifact(
        conversation,
        planArtifact: planArtifact,
        now: DateTime.now(),
      ),
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<bool> refreshCurrentWorkflowProjectionFromApprovedPlan() async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return false;
    }

    final approvedMarkdown = conversation.effectiveExecutionDocument;
    if (approvedMarkdown == null) {
      return false;
    }

    try {
      final projection =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: approvedMarkdown,
          );
      final stabilizedWorkflowSpec =
          ConversationPlanProjectionService.stabilizeTaskIds(
            previousTasks: conversation.projectedExecutionTasks,
            workflowSpec: projection.workflowSpec,
            anchoredTaskIndexes: projection.anchoredTaskIndexes,
          );
      await updateCurrentWorkflow(
        workflowStage: projection.workflowStage,
        workflowSpec: stabilizedWorkflowSpec,
        workflowSourceHash: projection.sourceHash,
        workflowDerivedAt: projection.derivedAt,
        preserveWorkflowProjection: true,
      );
      await retainExecutionTaskProgress(
        stabilizedWorkflowSpec.tasks.map((task) => task.id).toSet(),
      );
      await retainOpenQuestionProgress(stabilizedWorkflowSpec.openQuestions);
      return true;
    } on FormatException {
      return false;
    }
  }

  Future<void> enterPlanningSession() async {
    await _updateCurrentExecutionMode(ConversationExecutionMode.planning);
  }

  Future<void> exitPlanningSession() async {
    await _updateCurrentExecutionMode(ConversationExecutionMode.normal);
  }

  Future<void> _updateCurrentExecutionMode(
    ConversationExecutionMode executionMode,
  ) async {
    final conversation = state.currentConversation;
    if (conversation == null || conversation.executionMode == executionMode) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      executionMode: executionMode,
      compactionArtifact: _buildCompactionArtifact(
        conversation,
        executionMode: executionMode,
        now: DateTime.now(),
      ),
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  Future<void> rebuildCurrentConversationCompaction() async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      compactionArtifact: _buildCompactionArtifact(
        conversation,
        now: DateTime.now(),
      ),
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }

  /// Returns messages for the current conversation.
  List<Message> getCurrentMessages() {
    return state.currentConversation?.messages ?? [];
  }

  List<ConversationExecutionTaskEvent> _appendExecutionEvent(
    List<ConversationExecutionTaskEvent> existingEvents, {
    required ConversationExecutionTaskEventType? eventType,
    required DateTime eventTimestamp,
    required ConversationWorkflowTaskStatus status,
    required ConversationExecutionValidationStatus validationStatus,
    required String summary,
    required String blockedReason,
    required String validationCommand,
    required String validationSummary,
  }) {
    if (eventType == null) {
      return existingEvents.toList(growable: false);
    }

    final nextEvents = [...existingEvents];
    nextEvents.add(
      ConversationExecutionTaskEvent(
        type: eventType,
        createdAt: eventTimestamp,
        summary: summary,
        status: status,
        validationStatus: validationStatus,
        blockedReason: blockedReason,
        validationCommand: validationCommand,
        validationSummary: validationSummary,
      ),
    );

    const maxEventsPerTask = 12;
    if (nextEvents.length <= maxEventsPerTask) {
      return nextEvents;
    }
    return nextEvents.sublist(nextEvents.length - maxEventsPerTask);
  }

  ConversationCompactionArtifact? _buildCompactionArtifact(
    Conversation conversation, {
    List<Message>? messages,
    ConversationPlanArtifact? planArtifact,
    ConversationExecutionMode? executionMode,
    DateTime? now,
  }) {
    final resolvedMessages = messages ?? conversation.messages;
    final resolvedPlanArtifact = planArtifact ?? conversation.planArtifact;
    final resolvedExecutionMode = executionMode ?? conversation.executionMode;
    final planDocument =
        (resolvedPlanArtifact ?? const ConversationPlanArtifact())
            .displayMarkdown(
              isPlanning:
                  resolvedExecutionMode == ConversationExecutionMode.planning,
            );

    return ConversationCompactionService.buildArtifact(
      messages: resolvedMessages,
      planDocument: planDocument,
      now: now,
    );
  }
}
