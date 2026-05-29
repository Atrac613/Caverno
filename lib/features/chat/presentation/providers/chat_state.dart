import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';

part 'chat_state.freezed.dart';

enum ContextTokenPressureLevel { normal, warning, critical }

enum ChatInteractionOrigin { local, remote }

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
class PendingSshConnect {
  PendingSshConnect({
    required this.id,
    required this.host,
    required this.port,
    required this.username,
    required this.savedPassword,
    required this.completer,
  });

  final String id;
  final String host;
  final int port;
  final String username;

  /// Pre-loaded password for this (host, port, username) if one was saved
  /// previously in secure storage.
  final String? savedPassword;

  final Completer<SshConnectApproval?> completer;
}

/// Pending SSH command execution awaiting per-command user approval.
class PendingSshCommand {
  PendingSshCommand({
    required this.id,
    required this.command,
    required this.reason,
    required this.host,
    required this.username,
    required this.completer,
  });

  final String id;
  final String command;
  final String? reason;
  final String host;
  final String username;
  final Completer<bool> completer;
}

/// Pending git command execution awaiting user approval for write operations.
class PendingGitCommand {
  PendingGitCommand({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.reason,
    required this.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String id;
  final String command;
  final String workingDirectory;
  final String? reason;
  final Completer<bool> completer;
  final ChatInteractionOrigin origin;
}

/// Pending local shell command awaiting user approval.
class PendingLocalCommand {
  PendingLocalCommand({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.reason,
    required this.warningTitle,
    required this.warningMessage,
    required this.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String id;
  final String command;
  final String workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
  final Completer<LocalCommandApproval> completer;
  final ChatInteractionOrigin origin;
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
class PendingComputerUseAction {
  PendingComputerUseAction({
    required this.id,
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
    required this.completer,
  });

  final String id;
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
  final Completer<ComputerUseActionApprovalDecision> completer;
}

/// Pending local file operation awaiting user approval.
class PendingFileOperation {
  PendingFileOperation({
    required this.id,
    required this.operation,
    required this.path,
    required this.preview,
    required this.reason,
    required this.completer,
    this.origin = ChatInteractionOrigin.local,
  });

  final String id;
  final String operation;
  final String path;
  final String preview;
  final String? reason;
  final Completer<bool> completer;
  final ChatInteractionOrigin origin;
}

/// Pending BLE connect request awaiting user confirmation in the UI.
class PendingBleConnect {
  PendingBleConnect({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.completer,
  });

  final String id;
  final String deviceId;
  final String? deviceName;
  final Completer<bool> completer;
}

class AskUserQuestionOption {
  const AskUserQuestionOption({
    required this.id,
    required this.label,
    this.description = '',
    this.preview = '',
  });

  final String id;
  final String label;
  final String description;
  final String preview;
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
    this.origin = ChatInteractionOrigin.local,
  });

  final String id;
  final String content;
  final String? imageBase64;
  final String? imageMimeType;
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
            languageCode == other.languageCode &&
            isVoiceMode == other.isVoiceMode &&
            bypassPlanMode == other.bypassPlanMode &&
            origin == other.origin;
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    imageBase64,
    imageMimeType,
    languageCode,
    isVoiceMode,
    bypassPlanMode,
    origin,
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
abstract class ChatState with _$ChatState {
  const factory ChatState({
    required List<Message> messages,
    @Default([]) List<QueuedChatMessage> queuedMessages,
    required bool isLoading,
    String? error,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    @Default(0) int estimatedPromptTokens,
    @Default(ContextTokenPressureLevel.normal)
    ContextTokenPressureLevel contextTokenPressureLevel,
    @Default(false) bool promptCompactionActive,
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
    // File mutation tool UI flow.
    PendingFileOperation? pendingFileOperation,
    // BLE tool UI flow — same Completer-based pattern as SSH.
    PendingBleConnect? pendingBleConnect,
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
  }) = _ChatState;

  factory ChatState.initial() =>
      const ChatState(messages: [], isLoading: false);
}
