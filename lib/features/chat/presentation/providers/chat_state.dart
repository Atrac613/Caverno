import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/message.dart';

part 'chat_state.freezed.dart';

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
  });

  final String id;
  final String command;
  final String workingDirectory;
  final String? reason;
  final Completer<bool> completer;
}

/// Pending local shell command awaiting user approval.
class PendingLocalCommand {
  PendingLocalCommand({
    required this.id,
    required this.command,
    required this.workingDirectory,
    required this.reason,
    required this.completer,
  });

  final String id;
  final String command;
  final String workingDirectory;
  final String? reason;
  final Completer<bool> completer;
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
  });

  final String id;
  final String operation;
  final String path;
  final String preview;
  final String? reason;
  final Completer<bool> completer;
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
    required bool isLoading,
    String? error,
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    // SSH tool UI flow — holders contain Completers so they live outside
    // the freezed equality graph.
    PendingSshConnect? pendingSshConnect,
    PendingSshCommand? pendingSshCommand,
    // Git tool UI flow — same Completer-based pattern as SSH.
    PendingGitCommand? pendingGitCommand,
    // Local shell tool UI flow.
    PendingLocalCommand? pendingLocalCommand,
    // File mutation tool UI flow.
    PendingFileOperation? pendingFileOperation,
    // BLE tool UI flow — same Completer-based pattern as SSH.
    PendingBleConnect? pendingBleConnect,
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
