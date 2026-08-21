import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/execution_snapshot_projector.dart';

final class TurnOwnerSnapshot {
  TurnOwnerSnapshot({
    required this.owner,
    required List<Message> messages,
    required this.latestUserContent,
    required this.hasAttachments,
    required String? projectRoot,
    required LlmSessionLogContext sessionLogContext,
    required this.isCodingWorkspaceOrMode,
    required this.isPlanning,
    required this.hasPendingAutoContinueExecutionWorkflow,
    required ConversationWorkflowTask? savedTask,
    required Set<String>? allowedToolNames,
    String? ownerRepositoryPath,
    String? ownerWorktreePath,
    Message? hiddenPrompt,
    this.persistHiddenPromptAssistantResponse = false,
    this.temporalReferenceContext,
  }) : messages = List<Message>.unmodifiable(messages),
       projectRoot = _normalizePath(projectRoot),
       ownerRepositoryPath = _normalizePath(ownerRepositoryPath),
       ownerWorktreePath = _normalizePath(ownerWorktreePath),
       sessionLogContext = _freezeSessionLogContext(sessionLogContext),
       savedTask = savedTask?.copyWith(
         targetFiles: List<String>.unmodifiable(savedTask.targetFiles),
       ),
       hiddenPrompt = hiddenPrompt?.copyWith(
         participantToolNames: List<String>.unmodifiable(
           hiddenPrompt.participantToolNames,
         ),
       ),
       allowedToolNames = allowedToolNames == null
           ? null
           : Set<String>.unmodifiable(allowedToolNames);

  factory TurnOwnerSnapshot.capture({
    required ChatTurnOwner owner,
    required List<Message> messages,
    required Message? turnUserMessage,
    required String? projectRoot,
    required LlmSessionLogContext sessionLogContext,
    required Conversation? conversation,
    required AssistantMode? assistantModeOverride,
    required AssistantMode configuredAssistantMode,
    required ConversationWorkflowTask? savedTask,
    required Set<String>? allowedToolNames,
    String? ownerRepositoryPath,
    String? ownerWorktreePath,
    Message? hiddenPrompt,
    bool persistHiddenPromptAssistantResponse = false,
    String? temporalReferenceContext,
  }) => TurnOwnerSnapshot(
    owner: owner,
    messages: messages,
    latestUserContent: _latestUserContent(messages, turnUserMessage),
    hasAttachments: _hasAttachments(messages, turnUserMessage),
    projectRoot: projectRoot,
    sessionLogContext: sessionLogContext,
    isCodingWorkspaceOrMode:
        conversation?.workspaceMode == WorkspaceMode.coding ||
        assistantModeOverride == AssistantMode.coding ||
        configuredAssistantMode == AssistantMode.coding,
    isPlanning: conversation?.isPlanningSession ?? false,
    hasPendingAutoContinueExecutionWorkflow:
        _hasPendingAutoContinueExecutionWorkflow(conversation),
    savedTask: savedTask,
    allowedToolNames: allowedToolNames,
    ownerRepositoryPath: ownerRepositoryPath,
    ownerWorktreePath: ownerWorktreePath,
    hiddenPrompt: hiddenPrompt,
    persistHiddenPromptAssistantResponse: persistHiddenPromptAssistantResponse,
    temporalReferenceContext: temporalReferenceContext,
  );

  static LlmSessionLogContext buildSessionLogContext({
    required Conversation? conversation,
    required String? targetConversationId,
    required String? fallbackConversationId,
    required AssistantMode configuredAssistantMode,
    required bool hasHiddenPrompt,
    required bool isRemoteInteraction,
  }) {
    final workspaceMode =
        conversation?.workspaceMode ??
        (configuredAssistantMode == AssistantMode.coding ||
                configuredAssistantMode == AssistantMode.plan
            ? WorkspaceMode.coding
            : WorkspaceMode.chat);
    final resolvedConversationId =
        targetConversationId ??
        conversation?.id ??
        fallbackConversationId ??
        'unassigned';
    return LlmSessionLogContext(
      workspaceMode: workspaceMode,
      sessionId: resolvedConversationId,
      sessionTitle: conversation?.title,
      conversationId: resolvedConversationId,
      phase: hasHiddenPrompt
          ? 'hidden_prompt'
          : (isRemoteInteraction ? 'remote_interaction' : 'chat_turn'),
    );
  }

  static ConversationWorkflowTask? savedTaskFor(Conversation? conversation) {
    if (conversation == null) return null;
    final task =
        ConversationPlanExecutionCoordinator.validationTask(conversation) ??
        ConversationPlanExecutionCoordinator.executionFocusTask(conversation);
    return task?.copyWith(
      targetFiles: List<String>.unmodifiable(task.targetFiles),
    );
  }

  final ChatTurnOwner owner;
  final List<Message> messages;
  final String latestUserContent;
  final bool hasAttachments;
  final String? projectRoot;
  final LlmSessionLogContext sessionLogContext;
  final bool isCodingWorkspaceOrMode;
  final bool isPlanning;
  final bool hasPendingAutoContinueExecutionWorkflow;
  final ConversationWorkflowTask? savedTask;
  final String? ownerRepositoryPath;
  final String? ownerWorktreePath;
  final Message? hiddenPrompt;
  final bool persistHiddenPromptAssistantResponse;
  final String? temporalReferenceContext;

  /// Null means the full catalog is available. An empty set means the
  /// owner-specific request preparation exposed no tools.
  final Set<String>? allowedToolNames;

  TurnOwnerSnapshot withAllowedToolNames(Set<String>? names) =>
      _copy(messages, names);

  TurnOwnerSnapshot withMessages(List<Message> ownerMessages) =>
      _copy(ownerMessages, allowedToolNames);

  TurnOwnerSnapshot _copy(
    List<Message> ownerMessages,
    Set<String>? ownerAllowedToolNames,
  ) => TurnOwnerSnapshot(
    owner: owner,
    messages: ownerMessages,
    latestUserContent: latestUserContent,
    hasAttachments: hasAttachments,
    projectRoot: projectRoot,
    sessionLogContext: sessionLogContext,
    isCodingWorkspaceOrMode: isCodingWorkspaceOrMode,
    isPlanning: isPlanning,
    hasPendingAutoContinueExecutionWorkflow:
        hasPendingAutoContinueExecutionWorkflow,
    savedTask: savedTask,
    allowedToolNames: ownerAllowedToolNames,
    ownerRepositoryPath: ownerRepositoryPath,
    ownerWorktreePath: ownerWorktreePath,
    hiddenPrompt: hiddenPrompt,
    persistHiddenPromptAssistantResponse: persistHiddenPromptAssistantResponse,
    temporalReferenceContext: temporalReferenceContext,
  );

  static String? _normalizePath(String? path) {
    final normalized = path?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static LlmSessionLogContext _freezeSessionLogContext(
    LlmSessionLogContext context,
  ) {
    return LlmSessionLogContext(
      workspaceMode: context.workspaceMode,
      sessionId: context.sessionId,
      sessionTitle: context.sessionTitle,
      conversationId: context.conversationId,
      routineId: context.routineId,
      routineRunId: context.routineRunId,
      phase: context.phase,
      participantId: context.participantId,
      participantName: context.participantName,
      participantRoleLabel: context.participantRoleLabel,
      participantToolsEnabled: context.participantToolsEnabled,
      participantToolNames: List<String>.unmodifiable(
        context.participantToolNames,
      ),
    );
  }

  static String _latestUserContent(
    List<Message> messages,
    Message? turnUserMessage,
  ) {
    final turnContent = turnUserMessage?.content.trim() ?? '';
    if (turnContent.isNotEmpty) return turnContent;
    for (final message in messages.reversed) {
      if (message.role != MessageRole.user) continue;
      final content = message.content.trim();
      if (content.isNotEmpty) return content;
    }
    return '';
  }

  static bool _hasAttachments(
    List<Message> messages,
    Message? turnUserMessage,
  ) =>
      _messageHasAttachment(turnUserMessage) ||
      messages.any(_messageHasAttachment);

  static bool _messageHasAttachment(Message? message) {
    return (message?.imageBase64?.isNotEmpty ?? false) ||
        (message?.originalImagePath?.isNotEmpty ?? false) ||
        // Omitting video made a turn carrying one look like bare text here.
        (message?.hasVideoAttachment ?? false);
  }

  static bool _hasPendingAutoContinueExecutionWorkflow(
    Conversation? conversation,
  ) {
    final goal = conversation?.goal;
    if (conversation == null ||
        goal == null ||
        !goal.isActive ||
        !goal.autoContinue ||
        conversation.workflowStage != ConversationWorkflowStage.implement) {
      return false;
    }
    final execution = const ExecutionSnapshotProjector().project(conversation);
    return execution.action == ExecutionSnapshotAction.execute &&
        execution.remainingTaskCount > 0 &&
        execution.unresolvedQuestionCount == 0;
  }
}

final class TurnOwnerSnapshotRegistry {
  final Map<ChatTurnOwner, TurnOwnerSnapshot> _snapshots =
      <ChatTurnOwner, TurnOwnerSnapshot>{};
  int get length => _snapshots.length;
  bool get isEmpty => _snapshots.isEmpty;
  TurnOwnerSnapshot? snapshotFor(ChatTurnOwner owner) => _snapshots[owner];
  void capture(TurnOwnerSnapshot snapshot) =>
      _snapshots[snapshot.owner] = snapshot;

  bool updateAllowedToolNames(
    ChatTurnOwner owner,
    Set<String>? allowedToolNames,
  ) {
    final snapshot = _snapshots[owner];
    if (snapshot == null) return false;
    _snapshots[owner] = snapshot.withAllowedToolNames(allowedToolNames);
    return true;
  }

  bool updateMessages(ChatTurnOwner owner, List<Message> messages) {
    final snapshot = _snapshots[owner];
    if (snapshot == null) return false;
    _snapshots[owner] = snapshot.withMessages(messages);
    return true;
  }

  TurnOwnerSnapshot? dispose(ChatTurnOwner owner) => _snapshots.remove(owner);

  void clear() => _snapshots.clear();
}
