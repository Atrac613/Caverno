import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/watch_bridge_service.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/chat_state.dart';
import '../../chat/presentation/providers/conversations_notifier.dart'
    show ConversationsState, conversationsNotifierProvider,
        defaultConversationTitle;
import '../../chat/presentation/providers/pending_approval_resolution.dart';
import '../domain/watch_approval_mapper.dart';
import '../domain/watch_command.dart';
import '../domain/watch_snapshot.dart';

final watchBridgeServiceProvider = Provider<WatchBridgeService>((ref) {
  final service = MethodChannelWatchBridgeService();
  ref.onDispose(service.dispose);
  return service;
});

final watchSessionProvider =
    NotifierProvider<WatchSessionNotifier, WatchSessionState>(
      WatchSessionNotifier.new,
    );

class WatchSessionState {
  const WatchSessionState({
    this.isAvailable = false,
    this.lastSequence = 0,
    this.lastPushedAt,
    this.lastError,
  });

  final bool isAvailable;
  final int lastSequence;
  final DateTime? lastPushedAt;
  final String? lastError;

  WatchSessionState copyWith({
    bool? isAvailable,
    int? lastSequence,
    DateTime? lastPushedAt,
    String? lastError,
    bool clearError = false,
  }) => WatchSessionState(
    isAvailable: isAvailable ?? this.isAvailable,
    lastSequence: lastSequence ?? this.lastSequence,
    lastPushedAt: lastPushedAt ?? this.lastPushedAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// Mirrors this device's chat state to the paired Apple Watch and applies the
/// commands that come back.
///
/// This is the watch counterpart of `RemoteCodingServerNotifier`: same idea
/// (an external surface drives `ChatNotifier`), different transport and a
/// different trust model. See [WatchApprovalMapper] for why the watch is
/// treated as part of this device rather than as a paired remote principal.
class WatchSessionNotifier extends Notifier<WatchSessionState> {
  static const WatchApprovalMapper _approvals = WatchApprovalMapper();

  late final WatchBridgeService _bridge;
  StreamSubscription<WatchCommand>? _commandSubscription;
  int _sequence = 0;
  DateTime? _turnStartedAt;
  String _turnId = '';
  String _streamedPrefix = '';

  @override
  WatchSessionState build() {
    _bridge = ref.read(watchBridgeServiceProvider);

    ref.listen<ChatState>(chatNotifierProvider, (previous, next) {
      _trackTurnBoundary(previous, next);
      unawaited(_pushStreamDelta(next));
      unawaited(_pushSnapshot(next));
    });
    ref.listen<ConversationsState>(conversationsNotifierProvider, (_, _) {
      unawaited(_pushSnapshot(ref.read(chatNotifierProvider)));
    });

    _commandSubscription = _bridge.commands.listen(_handleCommand);
    ref.onDispose(() {
      unawaited(_commandSubscription?.cancel());
    });

    unawaited(_refreshAvailability());
    return const WatchSessionState();
  }

  Future<void> _refreshAvailability() async {
    final available = await _bridge.isAvailable();
    if (!ref.mounted) return;
    state = state.copyWith(isAvailable: available);
  }

  /// Records when a turn starts so the watch can show elapsed time without the
  /// phone having to push a tick every second.
  void _trackTurnBoundary(ChatState? previous, ChatState next) {
    final wasLoading = previous?.isLoading ?? false;
    if (!wasLoading && next.isLoading) {
      _turnStartedAt = DateTime.now();
      // A new turn resets the stream cursor; without this the watch would only
      // ever hear the tail of the second answer that differs from the first.
      _turnId = DateTime.now().microsecondsSinceEpoch.toString();
      _streamedPrefix = '';
    } else if (wasLoading && !next.isLoading) {
      _turnStartedAt = null;
    }
  }

  /// Pushes only the newly appended answer text.
  ///
  /// Snapshots coalesce — the OS may drop an intermediate application context —
  /// which is correct for state but would silently swallow sentences the watch
  /// is reading aloud. Deltas go over the message path instead, which does not
  /// coalesce.
  Future<void> _pushStreamDelta(ChatState chatState) async {
    if (!state.isAvailable) return;
    final text = _lastAssistantText(chatState.messages);
    if (text.isEmpty || !text.startsWith(_streamedPrefix)) {
      // The visible answer was replaced rather than extended (a guard rewrote
      // it, or the thread switched). Resend from the start.
      _streamedPrefix = '';
      if (text.isEmpty) return;
    }
    final delta = text.substring(_streamedPrefix.length);
    if (delta.isEmpty) return;
    _streamedPrefix = text;
    await _bridge.pushStreamChunk(
      turnId: _turnId,
      text: delta,
      isFinal: !chatState.isLoading,
    );
  }

  /// Builds the frame the watch renders.
  ///
  /// Deliberately does not reuse `RemoteCodingServerNotifier._buildSnapshot`:
  /// that projection carries the whole transcript and dashboard statistics and
  /// would not fit a WatchConnectivity payload.
  @visibleForTesting
  WatchSnapshot buildSnapshot(ChatState chatState) {
    _sequence += 1;
    final conversations = ref.read(conversationsNotifierProvider);
    final current = conversations.currentConversation;
    final approval = _approvals.map(chatState);
    final question = _approvals.mapQuestion(chatState);
    final startedAt = _turnStartedAt;

    return WatchSnapshot(
      sequence: _sequence,
      generatedAt: DateTime.now().toUtc(),
      conversationId: current?.id,
      conversationTitle: _titleFor(current?.title),
      status: _statusFor(chatState, approval: approval, question: question),
      lastAssistantText: _lastAssistantText(chatState.messages),
      approval: approval,
      question: question,
      elapsedSeconds: startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds,
      queuedCount: chatState.queuedMessages.length,
      busyThreadCount: chatState.busyConversationIds.length,
      error: chatState.error,
    );
  }

  /// Drops the untitled-conversation sentinel.
  ///
  /// `defaultConversationTitle` is a marker, not a label: every other surface
  /// substitutes something for it, and passing it through put a literal
  /// `__new_conversation__` on the watch. An empty title is right here rather
  /// than an English stand-in, because the watch already falls back to its own
  /// idle/working label and the phone has no business hardcoding a string it
  /// cannot localise for the watch.
  String _titleFor(String? title) {
    final normalized = title?.trim() ?? '';
    return normalized == defaultConversationTitle ? '' : normalized;
  }

  WatchTurnStatus _statusFor(
    ChatState chatState, {
    required WatchApproval? approval,
    required WatchQuestion? question,
  }) {
    // A blocked turn outranks a running one: the watch exists to unblock, and
    // "streaming" would hide the very thing the user must act on.
    if (approval != null) return WatchTurnStatus.waitingApproval;
    if (question != null) return WatchTurnStatus.waitingQuestion;
    if (chatState.isLoading) return WatchTurnStatus.streaming;
    if (chatState.error?.isNotEmpty == true) return WatchTurnStatus.error;
    return WatchTurnStatus.idle;
  }

  String _lastAssistantText(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != MessageRole.assistant) continue;
      final content = message.content.trim();
      if (content.isNotEmpty) return content;
    }
    return '';
  }

  Future<void> _pushSnapshot(ChatState chatState) async {
    if (!state.isAvailable) return;
    final snapshot = buildSnapshot(chatState);
    await _bridge.pushSnapshot(snapshot);
    if (!ref.mounted) return;
    state = state.copyWith(
      lastSequence: snapshot.sequence,
      lastPushedAt: snapshot.generatedAt,
    );
  }

  @visibleForTesting
  Future<void> handleCommandForTest(WatchCommand command) =>
      _handleCommand(command);

  @visibleForTesting
  Future<void> pushStreamDeltaForTest(String assistantText) => _pushStreamDelta(
    ChatState(
      messages: [
        Message(
          id: 'assistant-1',
          content: assistantText,
          role: MessageRole.assistant,
          timestamp: DateTime.utc(2026, 9, 1),
        ),
      ],
      isLoading: true,
    ),
  );

  Future<void> _handleCommand(WatchCommand command) async {
    if (!WatchCommand.allowed.contains(command.type)) {
      await _fail(
        command,
        code: 'unsupported_command',
        message: 'Unsupported watch command: ${command.type}',
      );
      return;
    }

    switch (command.type) {
      case WatchCommand.sendMessage:
        await _handleSendMessage(command);
      case WatchCommand.resolveApproval:
        await _handleResolveApproval(command);
      case WatchCommand.resolveQuestion:
        await _handleResolveQuestion(command);
      case WatchCommand.cancelStreaming:
        ref.read(chatNotifierProvider.notifier).cancelStreaming();
        await _succeed(command);
      case WatchCommand.requestSnapshot:
        await _pushSnapshot(ref.read(chatNotifierProvider));
        await _succeed(command);
    }
  }

  Future<void> _handleSendMessage(WatchCommand command) async {
    final content = (command.payload['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) {
      await _fail(
        command,
        code: 'empty_message',
        message: 'Message content is required.',
      );
      return;
    }
    // Sent as a local interaction, not a remote one: the watch is a peripheral
    // of this device, so its turns must stay resolvable from the iPhone UI.
    unawaited(
      ref
          .read(chatNotifierProvider.notifier)
          .sendMessage(
            content,
            languageCode:
                (command.payload['languageCode'] as String?) ?? 'en',
            isVoiceMode: command.payload['isVoiceMode'] == true,
            origin: ChatInteractionOrigin.local,
          ),
    );
    await _succeed(command);
  }

  Future<void> _handleResolveApproval(WatchCommand command) async {
    final approvalId = (command.payload['approvalId'] as String?)?.trim() ?? '';
    final approved = command.payload['approved'] == true;
    final pending = _approvals.map(ref.read(chatNotifierProvider));
    if (pending == null || pending.id != approvalId) {
      await _fail(
        command,
        code: 'approval_not_found',
        message: 'This approval is no longer pending.',
      );
      return;
    }
    if (!pending.canResolveOnWatch) {
      await _fail(
        command,
        code: 'approval_requires_phone',
        message: 'This approval must be completed on the iPhone.',
      );
      return;
    }
    if (!resolveApprovalById(
      ref.read(chatNotifierProvider.notifier),
      id: approvalId,
      approved: approved,
    )) {
      await _fail(
        command,
        code: 'approval_not_found',
        message: 'This approval is no longer pending.',
      );
      return;
    }
    await _succeed(command);
    await _pushSnapshot(ref.read(chatNotifierProvider));
  }

  Future<void> _handleResolveQuestion(WatchCommand command) async {
    final questionId = (command.payload['questionId'] as String?)?.trim() ?? '';
    final chatState = ref.read(chatNotifierProvider);
    final pending = chatState.pendingAskUserQuestion;
    if (pending == null ||
        pending.id != questionId ||
        _approvals.mapQuestion(chatState) == null) {
      await _fail(
        command,
        code: 'question_not_found',
        message: 'This question is no longer pending.',
      );
      return;
    }

    final cancelled = command.payload['cancelled'] == true;
    final selectedIds =
        (command.payload['selectedOptionIds'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
    final answer = cancelled
        ? null
        : AskUserQuestionAnswer(
            question: pending.question,
            selectedOptions: pending.options
                .where((option) => selectedIds.contains(option.id))
                .map(
                  (option) => AskUserQuestionSelection(
                    id: option.id,
                    label: option.label,
                    description: option.description,
                    preview: option.preview,
                  ),
                )
                .toList(growable: false),
            otherText:
                (command.payload['otherText'] as String?)?.trim() ?? '',
          );

    ref
        .read(chatNotifierProvider.notifier)
        .resolveAskUserQuestion(id: questionId, answer: answer);
    await _succeed(command);
    await _pushSnapshot(ref.read(chatNotifierProvider));
  }

  Future<void> _succeed(WatchCommand command) =>
      _bridge.sendCommandResult(WatchCommandResult.success(id: command.id));

  Future<void> _fail(
    WatchCommand command, {
    required String code,
    required String message,
  }) async {
    await _bridge.sendCommandResult(
      WatchCommandResult.failure(
        id: command.id,
        code: code,
        message: message,
      ),
    );
    if (!ref.mounted) return;
    state = state.copyWith(lastError: message);
  }
}
