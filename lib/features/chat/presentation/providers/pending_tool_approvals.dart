import 'dart:async';

import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/ssh_auth_credential.dart';

// The outstanding-approval registry moved out when this file reached its
// ratchet ceiling; re-exported so every existing importer still sees it.
export 'pending_tool_approval_registry.dart';

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
    required this.credential,
    required this.remember,
  });

  final String host;
  final int port;
  final String username;

  /// Password or private-key material chosen in the dialog.
  final SshAuthCredential credential;

  /// Whether to keep [credential] in the secure keychain for this target.
  final bool remember;
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
    required this.savedCredential,
    required this.identityCandidates,
    required super.completer,
  });

  final String host;
  final int port;
  final String username;

  /// Credential saved previously for this (host, port, username), if any.
  final SshAuthCredential? savedCredential;

  /// Private keys to offer for this host, best first.
  ///
  /// `~/.ssh/config` identities for the host come first when it has any,
  /// otherwise the existing default `~/.ssh/id_*` files. Resolved outside the
  /// widget so the dialog stays free of file IO and can be pumped in tests
  /// without depending on the host's real key files.
  final List<String> identityCandidates;

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
    this.remoteDeviceId,
  });

  final String command;
  final String workingDirectory;
  final String? reason;

  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;

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
    this.remoteDeviceId,
  });

  final String command;
  final String workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;

  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;

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
    this.remoteDeviceId,
  });

  final String operation;
  final String path;
  final String preview;
  final String? reason;

  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;

  @override
  bool get cancellationValue => false;
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

/// Pending confirmation of one material contract assumption (ANA0).
///
/// Raised from `MaterialContractAssumptionGuard`'s refusal site rather than
/// from plan review, because the guard refuses at the moment a mutation is
/// attempted: an affordance anywhere else leaves a blocked run with nowhere to
/// answer. One assumption per request — the ANA0 PR 3c/3e measurements found at
/// most three material marks in a plan and none in twelve of eighteen, so a
/// batch review would be a surface for a list that is normally empty.
///
/// [cancellationValue] is `false` on purpose. An expired turn must leave the
/// assumption unconfirmed: only the user may dispose of one, which is what
/// [ConversationContractItemProvenance.blocksExecution] exists to enforce.
class PendingAssumptionConfirmation extends PendingToolApproval<bool> {
  PendingAssumptionConfirmation({
    required super.owner,
    required super.id,
    required this.itemId,
    required this.kind,
    required this.itemText,
    required this.clarificationQuestion,
    required this.toolName,
    required super.completer,
    this.origin = ChatInteractionOrigin.local,
    this.remoteDeviceId,
  });

  /// The contract item to confirm, as
  /// [ConversationContractItemProvenance.itemId].
  final String itemId;
  final ConversationContractItemKind kind;

  /// The item's own text, resolved from the spec so the sheet can show what is
  /// being confirmed. The provenance record carries only an id, and the id is
  /// a hash.
  final String itemText;

  /// The model's own question about the assumption, when it wrote one.
  final String? clarificationQuestion;

  /// The mutation the guard refused, so the sheet can say what is blocked.
  final String toolName;

  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;

  @override
  bool get cancellationValue => false;
}
