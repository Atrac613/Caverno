import '../../domain/services/ask_user_question_policy.dart';
export '../../domain/services/ask_user_question_policy.dart'
    show AskUserQuestionOption;

import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/services/context_surgery_observation_service.dart';

part 'chat_state.freezed.dart';

enum ContextTokenPressureLevel { normal, warning, critical }

enum ChatInteractionOrigin { local, remote }

McpToolResult approvalTurnExpiredResult(String toolName) => McpToolResult(
  toolName: toolName,
  result: '',
  isSuccess: false,
  errorMessage: 'The approval turn expired before execution',
);

sealed class PendingToolApproval<T> {
  PendingToolApproval({
    required this.owner,
    required this.id,
    required this.completer,
  });

  final ChatTurnOwner owner;
  final String id;
  final Completer<T> completer;
  T get cancellationValue;

  void completeCancellation() {
    if (!completer.isCompleted) {
      completer.complete(cancellationValue);
    }
  }
}

/// Approval payload returned by the SSH connect dialog.
///
/// All fields may have been edited by the user before approval.
class SshConnectApproval {
  SshConnectApproval({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.savePassword,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final bool savePassword;
}

/// Pending SSH connect request awaiting user confirmation in the UI.
///
/// Populated by [ChatNotifier] when the LLM calls `ssh_connect`; the chat
/// page observes it via [ref.listen] and opens a dialog. The dialog
/// completes [completer] with an approval (possibly edited by the user)
/// or `null` when the user cancels.
class PendingSshConnect extends PendingToolApproval<SshConnectApproval?> {
  PendingSshConnect({
    required super.owner,
    required super.id,
    required this.host,
    required this.port,
    required this.username,
    required this.savedPassword,
    required super.completer,
  });

  final String host;
  final int port;
  final String username;

  /// Pre-loaded password for this (host, port, username) if one was saved
  /// previously in secure storage.
  final String? savedPassword;

  @override
  SshConnectApproval? get cancellationValue => null;
}

/// Pending SSH command execution awaiting per-command user approval.
class PendingSshCommand extends PendingToolApproval<bool> {
  PendingSshCommand({
    required super.owner,
    required super.id,
    required this.command,
    required this.reason,
    required this.host,
    required this.username,
    required super.completer,
  });

  final String command;
  final String? reason;
  final String host;
  final String username;

  @override
  bool get cancellationValue => false;
}

/// Pending git command execution awaiting user approval for write operations.
class PendingGitCommand extends PendingToolApproval<bool> {
  PendingGitCommand({
    required super.owner,
    required super.id,
    required this.command,
    required this.workingDirectory,
    required this.reason,
    required super.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String command;
  final String workingDirectory;
  final String? reason;

  final ChatInteractionOrigin origin;

  @override
  bool get cancellationValue => false;
}

/// Pending local shell command awaiting user approval.
class PendingLocalCommand extends PendingToolApproval<LocalCommandApproval> {
  PendingLocalCommand({
    required super.owner,
    required super.id,
    required this.command,
    required this.workingDirectory,
    required this.reason,
    required this.warningTitle,
    required this.warningMessage,
    required super.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String command;
  final String workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;

  final ChatInteractionOrigin origin;

  @override
  LocalCommandApproval get cancellationValue =>
      const LocalCommandApproval(approved: false);
}

class LocalCommandApproval {
  const LocalCommandApproval({
    required this.approved,
    this.rememberedRuleAction,
    this.rememberedRuleMatch,
  });

  final bool approved;
  final LocalCommandPermissionAction? rememberedRuleAction;
  final LocalCommandPermissionMatch? rememberedRuleMatch;

  bool get shouldRemember =>
      rememberedRuleAction != null && rememberedRuleMatch != null;
}

/// Decision for a macOS computer-use action approval request.
class ComputerUseActionApprovalDecision {
  const ComputerUseActionApprovalDecision({
    required this.approved,
    required this.armed,
    this.blockerCode,
  });

  final bool approved;
  final bool armed;
  final String? blockerCode;
}

/// Pending macOS computer-use action awaiting user approval.
class PendingComputerUseAction
    extends PendingToolApproval<ComputerUseActionApprovalDecision> {
  PendingComputerUseAction({
    required super.owner,
    required super.id,
    required this.toolName,
    required this.title,
    required this.riskCategory,
    required this.riskLabel,
    required this.warningMessage,
    required this.approveLabel,
    required this.requiresUserApproval,
    required this.requiresSmokeArming,
    required this.emergencyStop,
    required this.summary,
    required this.details,
    required this.targetSummary,
    required this.targetDetails,
    required this.exactTextPreview,
    required this.exactTextLength,
    required this.approvalBoundaries,
    required this.approvalBlockerCodes,
    required this.actionProposalNextAction,
    required this.visionObservationSummary,
    required this.visionObservationDetails,
    required this.reason,
    required super.completer,
  });

  final String toolName;
  final String title;
  final String riskCategory;
  final String riskLabel;
  final String warningMessage;
  final String approveLabel;
  final bool requiresUserApproval;
  final bool requiresSmokeArming;
  final bool emergencyStop;
  final String summary;
  final List<String> details;
  final String? targetSummary;
  final List<String> targetDetails;
  final String? exactTextPreview;
  final int? exactTextLength;
  final List<String> approvalBoundaries;
  final List<String> approvalBlockerCodes;
  final String? actionProposalNextAction;
  final String? visionObservationSummary;
  final List<String> visionObservationDetails;
  final String? reason;

  @override
  ComputerUseActionApprovalDecision get cancellationValue =>
      const ComputerUseActionApprovalDecision(
        approved: false,
        armed: false,
        blockerCode: 'approval_denied',
      );

  ComputerUseActionApprovalDecision resolve({
    required bool approved,
    required bool armed,
  }) => ComputerUseActionApprovalDecision(
    approved: approved && (!requiresSmokeArming || armed),
    armed: armed,
    blockerCode: approved && requiresSmokeArming && !armed
        ? 'arming_missing'
        : approved
        ? null
        : 'approval_denied',
  );
}

/// Pending sensitive browser action (fill / click / submit / eval / save)
/// awaiting user approval. Mirrors [PendingComputerUseAction] but carries only
/// the lighter context the browser approval sheet needs.
class PendingBrowserAction extends PendingToolApproval<bool> {
  PendingBrowserAction({
    required super.owner,
    required super.id,
    required this.toolName,
    required this.title,
    required this.riskLabel,
    required this.warningMessage,
    required this.approveLabel,
    required this.summary,
    required this.details,
    required this.targetSummary,
    required this.sensitiveValuePreview,
    required this.reason,
    required super.completer,
  });

  final String toolName;
  final String title;
  final String riskLabel;
  final String warningMessage;
  final String approveLabel;
  final String summary;
  final List<String> details;
  final String? targetSummary;

  /// Redacted preview for credential-like values (never the raw secret).
  final String? sensitiveValuePreview;
  final String? reason;

  @override
  bool get cancellationValue => false;
}

/// Pending local file operation awaiting user approval.
class PendingFileOperation extends PendingToolApproval<bool> {
  PendingFileOperation({
    required super.owner,
    required super.id,
    required this.operation,
    required this.path,
    required this.preview,
    required this.reason,
    required super.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String operation;
  final String path;
  final String preview;
  final String? reason;

  final ChatInteractionOrigin origin;

  @override
  bool get cancellationValue => false;
}

class PendingToolApprovalRegistry {
  final Map<ChatTurnOwner, Map<String, PendingToolApproval<dynamic>>>
  _requestsByOwner = {};
  final Map<String, PendingToolApproval<dynamic>> _requestsById = {};

  int get length => _requestsById.length;
  bool get isEmpty => _requestsById.isEmpty;

  void register<T>(PendingToolApproval<T> request) {
    if (_requestsById.containsKey(request.id)) {
      throw StateError(
        'A pending tool approval already uses ID ${request.id}.',
      );
    }
    _requestsById[request.id] = request;
    (_requestsByOwner[request.owner] ??= {})[request.id] = request;
  }

  Future<T> registerCurrent<T>(
    PendingToolApproval<T> request, {
    required bool ownerIsCurrent,
    required void Function() show,
  }) {
    if (!ownerIsCurrent) {
      request.completeCancellation();
    } else {
      register(request);
      show();
    }
    return request.completer.future;
  }

  T? find<T extends PendingToolApproval<dynamic>>(String id) {
    final request = _requestsById[id];
    return request is T ? request : null;
  }

  T? take<T extends PendingToolApproval<dynamic>>({
    required ChatTurnOwner owner,
    required String id,
  }) {
    final request = _requestsByOwner[owner]?[id];
    if (request is! T) {
      return null;
    }
    _remove(owner: owner, id: id);
    return request;
  }

  T? takeCurrent<T extends PendingToolApproval<dynamic>>({
    required String id,
    required bool Function(ChatTurnOwner owner) ownerIsCurrent,
    required void Function(PendingToolApproval<dynamic> request) clear,
  }) {
    final request = find<T>(id);
    if (request == null) return null;
    if (!ownerIsCurrent(request.owner)) {
      cancel(owner: request.owner, id: id);
      clear(request);
      return null;
    }
    final taken = take<T>(owner: request.owner, id: id);
    if (taken != null) clear(taken);
    return taken;
  }

  bool cancel({required ChatTurnOwner owner, required String id}) {
    final request = _remove(owner: owner, id: id);
    if (request == null) {
      return false;
    }
    request.completeCancellation();
    return true;
  }

  List<PendingToolApproval<dynamic>> cancelOwner(ChatTurnOwner owner) {
    final requests = _requestsByOwner.remove(owner);
    if (requests == null) {
      return const [];
    }
    for (final entry in requests.entries) {
      if (identical(_requestsById[entry.key], entry.value)) {
        _requestsById.remove(entry.key);
      }
    }
    final cancelled = requests.values.toList(growable: false);
    for (final request in cancelled) {
      request.completeCancellation();
    }
    return cancelled;
  }

  int cancelAll() {
    if (_requestsById.isEmpty) {
      return 0;
    }
    final requests = _requestsById.values.toList(growable: false);
    _requestsById.clear();
    _requestsByOwner.clear();
    for (final request in requests) {
      request.completeCancellation();
    }
    return requests.length;
  }

  PendingToolApproval<dynamic>? _remove({
    required ChatTurnOwner owner,
    required String id,
  }) {
    final ownerRequests = _requestsByOwner[owner];
    final request = ownerRequests?.remove(id);
    if (request == null) {
      return null;
    }
    if (ownerRequests!.isEmpty) {
      _requestsByOwner.remove(owner);
    }
    if (identical(_requestsById[id], request)) {
      _requestsById.remove(id);
    }
    return request;
  }
}

/// Pending BLE connect request awaiting user confirmation in the UI.
class PendingBleConnect extends PendingToolApproval<bool> {
  PendingBleConnect({
    required super.owner,
    required super.id,
    required this.deviceId,
    required this.deviceName,
    required super.completer,
  });

  final String deviceId;
  final String? deviceName;

  @override
  bool get cancellationValue => false;
}

class PendingSerialOpen extends PendingToolApproval<bool> {
  PendingSerialOpen({
    required super.owner,
    required super.id,
    required this.portName,
    required this.baudRate,
    required super.completer,
  });

  final String portName;
  final int baudRate;

  @override
  bool get cancellationValue => false;
}

/// Pending read-only participant tool execution awaiting user approval.
class PendingParticipantToolApproval extends PendingToolApproval<bool> {
  PendingParticipantToolApproval({
    required super.owner,
    required super.id,
    required this.participantId,
    required this.participantName,
    required this.participantRoleLabel,
    required this.toolName,
    required this.arguments,
    required this.reason,
    required super.completer,
  });

  final String participantId;
  final String participantName;
  final String participantRoleLabel;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String? reason;

  int get interactionGeneration => owner.interactionGeneration;
  String get ownerConversationId => owner.conversationId;

  @override
  bool get cancellationValue => false;
}

class AskUserQuestionSelection {
  const AskUserQuestionSelection({
    required this.id,
    required this.label,
    this.description = '',
    this.preview = '',
  });

  final String id;
  final String label;
  final String description;
  final String preview;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    if (description.trim().isNotEmpty) 'description': description.trim(),
    if (preview.trim().isNotEmpty) 'preview': preview.trim(),
  };
}

class AskUserQuestionAnswer {
  const AskUserQuestionAnswer({
    required this.question,
    required this.selectedOptions,
    this.otherText = '',
  });

  final String question;
  final List<AskUserQuestionSelection> selectedOptions;
  final String otherText;

  bool get hasAnswer =>
      selectedOptions.isNotEmpty || otherText.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'question': question,
    'selected': selectedOptions.map((option) => option.toJson()).toList(),
    if (otherText.trim().isNotEmpty) 'other': otherText.trim(),
    'answer': [
      ...selectedOptions.map((option) => option.label),
      if (otherText.trim().isNotEmpty) otherText.trim(),
    ].join('; '),
  };
}

class PendingAskUserQuestion {
  PendingAskUserQuestion({
    required this.id,
    required this.conversationId,
    required this.question,
    required this.help,
    required this.options,
    required this.allowMultiple,
    required this.allowOther,
    required this.otherPlaceholder,
    required this.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String id;
  final String? conversationId;
  final String question;
  final String help;
  final List<AskUserQuestionOption> options;
  final bool allowMultiple;
  final bool allowOther;
  final String otherPlaceholder;
  final Completer<AskUserQuestionAnswer?> completer;

  /// Where the turn that raised this question originated. Mirrors the pending
  /// approval models so a question is only surfaced to a paired remote device
  /// when the turn itself came from that device.
  final ChatInteractionOrigin origin;
}

class WorkflowPlanningDecisionOption {
  const WorkflowPlanningDecisionOption({
    required this.id,
    required this.label,
    this.description = '',
  });

  final String id;
  final String label;
  final String description;
}

class WorkflowPlanningDecision {
  const WorkflowPlanningDecision({
    required this.id,
    required this.question,
    this.help = '',
    this.allowFreeText = false,
    this.freeTextPlaceholder = '',
    required this.options,
  });

  final String id;
  final String question;
  final String help;
  final bool allowFreeText;
  final String freeTextPlaceholder;
  final List<WorkflowPlanningDecisionOption> options;
}

class WorkflowPlanningDecisionAnswer {
  const WorkflowPlanningDecisionAnswer({
    required this.decisionId,
    required this.question,
    required this.optionId,
    required this.optionLabel,
  });

  final String decisionId;
  final String question;
  final String optionId;
  final String optionLabel;
}

class PendingWorkflowDecision {
  PendingWorkflowDecision({
    required this.id,
    required this.decision,
    required this.completer,
  });

  final String id;
  final WorkflowPlanningDecision decision;
  final Completer<WorkflowPlanningDecisionAnswer?> completer;
}

class QueuedChatMessage {
  const QueuedChatMessage({
    required this.id,
    required this.content,
    required this.imageBase64,
    required this.imageMimeType,
    required this.languageCode,
    required this.isVoiceMode,
    required this.bypassPlanMode,
    this.originalImagePath,
    this.originalImageMimeType,
    this.origin = ChatInteractionOrigin.local,
    this.conversationId,
  });

  /// The thread this message was typed in. A message queued behind another
  /// thread's turn must come back to its own thread, never to whichever one
  /// the user is looking at when the queue drains.
  final String? conversationId;

  final String id;
  final String content;
  final String? imageBase64;
  final String? imageMimeType;
  final String? originalImagePath;
  final String? originalImageMimeType;
  final String languageCode;
  final bool isVoiceMode;
  final bool bypassPlanMode;
  final ChatInteractionOrigin origin;

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is QueuedChatMessage &&
            id == other.id &&
            content == other.content &&
            imageBase64 == other.imageBase64 &&
            imageMimeType == other.imageMimeType &&
            originalImagePath == other.originalImagePath &&
            originalImageMimeType == other.originalImageMimeType &&
            languageCode == other.languageCode &&
            isVoiceMode == other.isVoiceMode &&
            bypassPlanMode == other.bypassPlanMode &&
            origin == other.origin &&
            conversationId == other.conversationId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    imageBase64,
    imageMimeType,
    originalImagePath,
    originalImageMimeType,
    languageCode,
    isVoiceMode,
    bypassPlanMode,
    origin,
    conversationId,
  );
}

@freezed
abstract class WorkflowProposalDraft with _$WorkflowProposalDraft {
  const factory WorkflowProposalDraft({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
  }) = _WorkflowProposalDraft;
}

@freezed
abstract class WorkflowTaskProposalDraft with _$WorkflowTaskProposalDraft {
  const factory WorkflowTaskProposalDraft({
    required List<ConversationWorkflowTask> tasks,
  }) = _WorkflowTaskProposalDraft;
}

@freezed
abstract class ParticipantTurnRuntime with _$ParticipantTurnRuntime {
  const factory ParticipantTurnRuntime({
    String? activeParticipantId,
    @Default('') String activeParticipantName,
    @Default('') String activeParticipantRoleLabel,
    int? activeParticipantColorValue,
    @Default(1) int currentRound,
    @Default(1) int maxRounds,
    @Default(false) bool multiRound,
    @Default(false) bool stopRequested,
    @Default(false) bool paused,
    @Default('') String activeToolName,
  }) = _ParticipantTurnRuntime;
}

@freezed
abstract class ChatState with _$ChatState {
  const factory ChatState({
    required List<Message> messages,
    @Default([]) List<QueuedChatMessage> queuedMessages,
    required bool isLoading,
    // Conversations with a running response, including ones the user is not
    // looking at. Lives in the state (not only in ActiveResponseRegistry) so
    // clearing the last entry notifies listeners; the thread list renders its
    // busy spinner from this.
    @Default(<String>{}) Set<String> busyConversationIds,
    // Threads blocked on an approval the user has not answered. Such a thread
    // is not working, so the sidebar says so instead of spinning forever.
    @Default(<String>{}) Set<String> approvalRequiredConversationIds,
    String? error,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    @Default(0) int estimatedPromptTokens,
    @Default(ContextTokenPressureLevel.normal)
    ContextTokenPressureLevel contextTokenPressureLevel,
    @Default(false) bool promptCompactionActive,
    @Default(ContextSurgeryObservationSnapshot.empty)
    ContextSurgeryObservationSnapshot contextSurgerySnapshot,
    ParticipantTurnRuntime? participantTurnRuntime,
    // SSH tool UI flow — holders contain Completers so they live outside
    // the freezed equality graph.
    PendingSshConnect? pendingSshConnect,
    PendingSshCommand? pendingSshCommand,
    // Git tool UI flow — same Completer-based pattern as SSH.
    PendingGitCommand? pendingGitCommand,
    // Local shell tool UI flow.
    PendingLocalCommand? pendingLocalCommand,
    // macOS computer-use tool UI flow.
    PendingComputerUseAction? pendingComputerUseAction,
    // Built-in browser sensitive-action UI flow.
    PendingBrowserAction? pendingBrowserAction,
    // File mutation tool UI flow.
    PendingFileOperation? pendingFileOperation,
    // BLE tool UI flow — same Completer-based pattern as SSH.
    PendingBleConnect? pendingBleConnect,
    // Serial port open UI flow — same Completer-based approval as BLE.
    PendingSerialOpen? pendingSerialOpen,
    // Participant read-only tool UI flow.
    PendingParticipantToolApproval? pendingParticipantToolApproval,
    // Generic model-initiated question UI flow.
    PendingAskUserQuestion? pendingAskUserQuestion,
    // Workflow planning choice UI flow.
    PendingWorkflowDecision? pendingWorkflowDecision,
    @Default(false) bool isGeneratingWorkflowProposal,
    WorkflowProposalDraft? workflowProposalDraft,
    String? workflowProposalError,
    @Default(false) bool isGeneratingTaskProposal,
    WorkflowTaskProposalDraft? taskProposalDraft,
    String? taskProposalError,
    @Default(0) int goalAutoContinueCount,
    @Default(0) int goalAutoContinueBudget,
    String? goalAutoContinueNotice,
  }) = _ChatState;

  factory ChatState.initial() =>
      const ChatState(messages: [], isLoading: false);
}
