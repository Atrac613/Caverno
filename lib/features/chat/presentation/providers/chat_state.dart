import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _ChatState;

  factory ChatState.initial() =>
      const ChatState(messages: [], isLoading: false);
}
