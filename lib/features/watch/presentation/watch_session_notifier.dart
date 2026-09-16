import 'dart:async';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/watch_bridge_service.dart';
import '../../../core/types/workspace_mode.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/chat_state.dart';
import '../../chat/presentation/providers/conversations_notifier.dart'
    show
        ConversationsState,
        conversationsNotifierProvider,
        defaultConversationTitle;
import '../../chat/presentation/providers/pending_approval_resolution.dart';
import '../../remote_coding/presentation/remote_coding_client_notifier.dart';
import '../domain/watch_approval_mapper.dart';
import '../domain/watch_command.dart';
import '../domain/watch_snapshot.dart';
import '../domain/watch_transcript_projector.dart';
import 'watch_remote_navigation.dart';

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
  static const WatchTranscriptProjector _transcripts =
      WatchTranscriptProjector();

  late final WatchBridgeService _bridge;
  late final WatchRemoteNavigation _remoteNavigation;
  String _lastTranscriptSource = 'local';
  StreamSubscription<WatchCommand>? _commandSubscription;
  bool _available = false;
  int _sequence = 0;
  final String _sourceInstanceId = const Uuid().v4();
  final int _sourceStartedAtMicros = DateTime.now()
      .toUtc()
      .microsecondsSinceEpoch;
  DateTime? _turnStartedAt;
  String _turnId = '';
  String _streamedPrefix = '';
  bool _streamFinalSent = false;
  Set<String> _assistantIdsBeforeTurn = const {};

  @override
  WatchSessionState build() {
    _bridge = ref.read(watchBridgeServiceProvider);
    _remoteNavigation = WatchRemoteNavigation(
      readRemote: () => ref.read(remoteCodingClientProvider),
      selectConversation: (id) =>
          ref.read(remoteCodingClientProvider.notifier).selectConversation(id),
      onChanged: () {
        if (_lastTranscriptSource != _remoteNavigation.source) {
          _lastTranscriptSource = _remoteNavigation.source;
          _streamedPrefix = '';
          _streamFinalSent = false;
        }
        if (ref.mounted) {
          unawaited(_pushSnapshot(ref.read(chatNotifierProvider)));
        }
      },
    );
    ref.onDispose(_remoteNavigation.dispose);

    ref.listen<ChatState>(chatNotifierProvider, (previous, next) {
      _trackTurnBoundary(previous, next);
      unawaited(_pushStreamDelta(next));
      unawaited(_pushSnapshot(next));
    });
    ref.listen<ConversationsState>(conversationsNotifierProvider, (_, _) {
      unawaited(_pushSnapshot(ref.read(chatNotifierProvider)));
    });
    // The second source (WATCH11). A desktop's approval reaches this phone
    // through Remote Coding, never through `ChatState`, so the wrist cannot see
    // one without watching here too.
    ref.listen<RemoteCodingClientState>(remoteCodingClientProvider, (
      previous,
      next,
    ) {
      _remoteNavigation.update(previous, next);
      unawaited(_pushSnapshot(ref.read(chatNotifierProvider)));
    });

    _commandSubscription = _bridge.commands.listen(_handleCommand);
    ref.onDispose(() {
      unawaited(_commandSubscription?.cancel());
    });

    unawaited(_ensureAvailable());
    return const WatchSessionState();
  }

  /// Resolves whether a watch is reachable, re-querying when the last answer
  /// was negative.
  ///
  /// `WCSession.activate()` is asynchronous, so an availability answer taken
  /// once at build time is a race: on a cold start the session is often still
  /// activating, and latching that `false` left the watch sitting on its
  /// connecting screen forever — observed after a simulator reboot, where the
  /// watch's `requestSnapshot` reached the phone and got no reply. A negative
  /// answer is therefore treated as "not yet", never as settled.
  Future<bool> _ensureAvailable() async {
    if (_available) return true;
    final available = await _bridge.isAvailable();
    // Tracked in a field rather than read back from [state]: build() calls this
    // before the notifier's state exists, and Riverpod throws on that read.
    _available = available;
    if (available && ref.mounted) {
      state = state.copyWith(isAvailable: true);
    }
    return available;
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
      _streamFinalSent = false;
      _assistantIdsBeforeTurn = {
        for (final message in previous?.messages ?? const <Message>[])
          if (message.role == MessageRole.assistant) message.id,
      };
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
    if (!await _ensureAvailable()) return;
    if (_remoteNavigation.source != 'local') return;
    final text = _activeTurnAssistantText(chatState.messages);
    if (text.isEmpty || !text.startsWith(_streamedPrefix)) {
      // The visible answer was replaced rather than extended (a guard rewrote
      // it, or the thread switched). Resend from the start.
      _streamedPrefix = '';
      if (text.isEmpty) return;
    }
    final delta = text.substring(_streamedPrefix.length);
    final isFinal = !chatState.isLoading;
    if (delta.isEmpty && (!isFinal || _streamFinalSent)) return;
    _streamedPrefix = text;
    await _bridge.pushStreamChunk(
      turnId: _turnId,
      text: delta,
      isFinal: isFinal,
    );
    if (isFinal) _streamFinalSent = true;
  }

  /// The newest answer created during the current turn.
  ///
  /// `ChatNotifier` marks the state as loading immediately after appending the
  /// new user message, before it appends the empty streaming assistant message.
  /// Reading the last assistant at that boundary would therefore resend the
  /// previous turn's answer as the first stream chunk.
  String _activeTurnAssistantText(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != MessageRole.assistant ||
          _assistantIdsBeforeTurn.contains(message.id)) {
        continue;
      }
      final content = ContentParser.parse(message.content).text.trim();
      if (content.isNotEmpty) return content;
    }
    return '';
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
    final approval = _currentApproval(chatState);
    final question = _currentQuestion(chatState);
    final browser = _remoteNavigation.snapshot();
    if (_remoteNavigation.source == 'remote') {
      final remote = ref.read(remoteCodingClientProvider);
      final confirmed =
          browser.selectionStatus == 'selected' &&
          remote.isConnected &&
          remote.selectedProjectId == browser.projectId &&
          remote.currentConversationId == browser.conversationId;
      final transcript = _transcripts.project(
        confirmed ? remote.messages : const <Message>[],
      );
      return WatchSnapshot(
        sequence: _sequence,
        generatedAt: DateTime.now().toUtc(),
        sourceInstanceId: _sourceInstanceId,
        sourceStartedAtMicros: _sourceStartedAtMicros,
        transcriptSource: 'remote',
        remoteBrowser: browser,
        conversationId: confirmed ? browser.conversationId : null,
        conversationTitle: confirmed ? browser.conversationTitle : '',
        workspaceMode: 'coding',
        lastAssistantText: transcript.lastAssistantText,
        messages: transcript.messages,
        messagesTruncated: transcript.messagesTruncated,
        approval: approval,
        question: question,
        status: approval != null
            ? WatchTurnStatus.waitingApproval
            : question != null
            ? WatchTurnStatus.waitingQuestion
            : confirmed && remote.isLoading
            ? WatchTurnStatus.streaming
            : confirmed && remote.error?.isNotEmpty == true
            ? WatchTurnStatus.error
            : WatchTurnStatus.idle,
        queuedCount: confirmed ? remote.queuedCount : 0,
        busyThreadCount: confirmed && remote.isLoading ? 1 : 0,
        error: confirmed ? remote.error : null,
      );
    }
    final goal = _goalFor(current);
    final startedAt = _turnStartedAt;
    final transcript = _transcripts.project(chatState.messages);

    return WatchSnapshot(
      sequence: _sequence,
      generatedAt: DateTime.now().toUtc(),
      sourceInstanceId: _sourceInstanceId,
      sourceStartedAtMicros: _sourceStartedAtMicros,
      conversationId: current?.id,
      conversationTitle: _titleFor(current?.title),
      workspaceMode: current?.workspaceMode.name ?? '',
      goal: goal,
      status: _statusFor(
        chatState,
        approval: approval,
        question: question,
        goal: current?.goal,
      ),
      lastAssistantText: transcript.lastAssistantText,
      messages: transcript.messages,
      messagesTruncated: transcript.messagesTruncated,
      approval: approval,
      question: question,
      elapsedSeconds: startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inSeconds,
      queuedCount: chatState.queuedMessages.length,
      busyThreadCount: chatState.busyConversationIds.length,
      conversations: _switchableConversations(conversations),
      conversationsTruncated:
          conversations.conversations.length > watchSnapshotMaxConversations,
      error: chatState.error,
      remoteBrowser: browser,
    );
  }

  /// Answers a question raised by a desktop, over the Remote Coding socket.
  ///
  /// The option ids come back from the wire model the card was built from, so
  /// a selection made on the wrist means the same thing the desktop asked.
  Future<void> _resolveRemoteQuestion(
    WatchCommand command,
    String questionId,
    WatchQuestion shown,
  ) async {
    final cancelled = command.payload['cancelled'] == true;
    final known = shown.options.map((option) => option.id).toSet();
    final selected =
        (command.payload['selectedOptionIds'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .map((id) => id.trim())
            .where(known.contains)
            .toList(growable: false);
    await ref
        .read(remoteCodingClientProvider.notifier)
        .resolveQuestion(
          questionId: questionId,
          selectedOptionIds: selected,
          otherText: (command.payload['otherText'] as String?)?.trim() ?? '',
          cancelled: cancelled,
        );
    await _succeed(command);
    await _pushSnapshot(ref.read(chatNotifierProvider));
  }

  /// The one approval the wrist should show, across both sources.
  ///
  /// Derived in one place so the card the watch renders and the request a
  /// resolution is checked against cannot disagree — which is what would let a
  /// tap answer something other than what was on screen.
  WatchApproval? _currentApproval(ChatState chatState) {
    final remote = ref.read(remoteCodingClientProvider);
    return _approvals.preferred(
      _approvals.map(chatState),
      _approvals.mapRemote(
        remote.pendingApproval,
        host: _remoteHostName(remote),
      ),
    );
  }

  WatchQuestion? _currentQuestion(ChatState chatState) {
    final remote = ref.read(remoteCodingClientProvider);
    return _approvals.preferredQuestion(
      _approvals.mapQuestion(chatState),
      _approvals.mapRemoteQuestion(
        remote.pendingQuestion,
        host: _remoteHostName(remote),
      ),
    );
  }

  /// What to call the desktop on a wrist card.
  ///
  /// Its configured name, falling back to the address it is reached at. Never
  /// empty for a remote card: the label is the point.
  String _remoteHostName(RemoteCodingClientState remote) {
    final name = remote.host?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final address = remote.host?.host.trim() ?? '';
    return address.isNotEmpty ? address : 'Desktop';
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

  /// Threads the watch may switch to.
  ///
  /// Capped at the source rather than only in the wire model so the projection
  /// never builds a list it is about to discard, and titled with the same
  /// sentinel handling as the header.
  List<WatchConversation> _switchableConversations(ConversationsState state) =>
      state.conversations
          .take(watchSnapshotMaxConversations)
          .map(
            (conversation) => WatchConversation(
              id: conversation.id,
              title: _titleFor(conversation.title),
              mode: conversation.workspaceMode == WorkspaceMode.chat
                  ? ''
                  : conversation.workspaceMode.name,
            ),
          )
          .toList(growable: false);

  /// Projects the thread's goal, or null when there is nothing to show.
  ///
  /// A disabled or objective-less goal is not projected at all: an empty
  /// affordance on a wrist is worse than none, and `hasObjective` is what every
  /// other surface already treats as "there is a goal here".
  WatchGoal? _goalFor(Conversation? conversation) {
    final goal = conversation?.goal;
    if (goal == null || !goal.enabled || !goal.hasObjective) return null;
    return WatchGoal(
      objective: goal.normalizedObjective ?? '',
      status: goal.status.name,
      completionSummary: goal.normalizedCompletionSummary ?? '',
      blockedReason: goal.normalizedBlockedReason ?? '',
    );
  }

  WatchTurnStatus _statusFor(
    ChatState chatState, {
    required WatchApproval? approval,
    required WatchQuestion? question,
    required ConversationGoal? goal,
  }) {
    // A blocked turn outranks a running one: the watch exists to unblock, and
    // "streaming" would hide the very thing the user must act on.
    if (approval != null) return WatchTurnStatus.waitingApproval;
    if (question != null) return WatchTurnStatus.waitingQuestion;
    if (chatState.isLoading) return WatchTurnStatus.streaming;
    if (chatState.error?.isNotEmpty == true) return WatchTurnStatus.error;
    // Ranked below an error but above idle. Nothing is running either way, and
    // rendering this as idle made a decision waiting for the person look like
    // a finished thread.
    if (goal?.isAwaitingConfirmation == true) {
      return WatchTurnStatus.awaitingGoalConfirmation;
    }
    return WatchTurnStatus.idle;
  }

  Future<void> _pushSnapshot(ChatState chatState) async {
    if (!await _ensureAvailable()) return;
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
  Future<void> pushStreamDeltaForTest(
    String assistantText, {
    bool isFinal = false,
  }) => _pushStreamDelta(
    ChatState(
      messages: [
        Message(
          id: 'assistant-1',
          content: assistantText,
          role: MessageRole.assistant,
          timestamp: DateTime.utc(2026, 9, 1),
        ),
      ],
      isLoading: !isFinal,
    ),
  );

  @visibleForTesting
  Future<void> pushStreamStateChangeForTest(
    ChatState? previous,
    ChatState next,
  ) {
    _trackTurnBoundary(previous, next);
    return _pushStreamDelta(next);
  }

  Future<void> _handleCommand(WatchCommand command) async {
    if (!WatchCommand.allowed.contains(command.type)) {
      await _fail(
        command,
        code: 'unsupported_command',
        message: 'Unsupported watch command: ${command.type}',
      );
      return;
    }

    // Goal and local thread controls never cross into Remote Coding. Send and
    // Stop have their own destination-bound paths below.
    if ({
          WatchCommand.resolveGoal,
          WatchCommand.selectConversation,
        }.contains(command.type) &&
        (_remoteNavigation.source != 'local' ||
            (command.payload['source'] ?? 'local') != 'local')) {
      await _fail(
        command,
        code: 'remote_input_unavailable',
        message: 'Use iPhone to send messages or control this remote thread.',
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
        await _handleCancelStreaming(command);
      case WatchCommand.requestSnapshot:
        await _pushSnapshot(ref.read(chatNotifierProvider));
        await _succeed(command);
      case WatchCommand.selectConversation:
        await _handleSelectConversation(command);
      case WatchCommand.resolveGoal:
        await _handleResolveGoal(command);
      case WatchCommand.selectSource:
      case WatchCommand.browseRemote:
      case WatchCommand.selectRemoteConversation:
        final result = await _remoteNavigation.handle(command);
        if (!ref.mounted) return;
        await _bridge.sendCommandResult(result);
        await _pushSnapshot(ref.read(chatNotifierProvider));
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
    final commandSource = command.payload['source'] as String? ?? 'local';
    if (commandSource == 'remote' || _remoteNavigation.source == 'remote') {
      await _handleRemoteSendMessage(command, content);
      return;
    }
    if (commandSource != 'local') {
      await _fail(
        command,
        code: 'invalid_source',
        message: 'The conversation source is invalid.',
      );
      return;
    }
    // The watch stamps the conversation it was showing when the text was
    // composed. `WatchSessionClient` falls back to `transferUserInfo` when the
    // phone is unreachable, which guarantees delivery but not promptness: a
    // message composed on one thread could otherwise land in whichever thread
    // happened to be current minutes later. Approvals do not need this because
    // their ids are unique and a stale one simply fails to resolve.
    final composedFor = (command.payload['conversationId'] as String?)?.trim();
    final current = ref
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.id;
    if (composedFor != null &&
        composedFor.isNotEmpty &&
        current != null &&
        composedFor != current) {
      await _fail(
        command,
        code: 'conversation_changed',
        message: 'That thread is no longer open. Send it again.',
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
            languageCode: (command.payload['languageCode'] as String?) ?? 'en',
            isVoiceMode: command.payload['isVoiceMode'] == true,
            origin: ChatInteractionOrigin.local,
          ),
    );
    await _succeed(command);
  }

  Future<void> _handleRemoteSendMessage(
    WatchCommand command,
    String content,
  ) async {
    final validation = _remoteNavigation.validateSelectedDestination(command);
    if (!validation.ok) {
      await _bridge.sendCommandResult(validation);
      return;
    }
    final result = await ref
        .read(remoteCodingClientProvider.notifier)
        .sendMessageToConversation(
          projectId: command.payload['projectId'] as String,
          conversationId: command.payload['conversationId'] as String,
          content: content,
          languageCode: (command.payload['languageCode'] as String?) ?? 'en',
          isVoiceMode: command.payload['isVoiceMode'] == true,
        );
    if (!ref.mounted) return;
    await _sendBoundCommandResult(command, result, action: 'Message');
    await _pushSnapshot(ref.read(chatNotifierProvider));
  }

  Future<void> _handleCancelStreaming(WatchCommand command) async {
    final commandSource = command.payload['source'] as String? ?? 'local';
    if (commandSource == 'remote' || _remoteNavigation.source == 'remote') {
      final validation = _remoteNavigation.validateSelectedDestination(command);
      if (!validation.ok) {
        await _bridge.sendCommandResult(validation);
        return;
      }
      final result = await ref
          .read(remoteCodingClientProvider.notifier)
          .cancelConversationStreaming(
            projectId: command.payload['projectId'] as String,
            conversationId: command.payload['conversationId'] as String,
          );
      if (!ref.mounted) return;
      await _sendBoundCommandResult(command, result, action: 'Stop');
      await _pushSnapshot(ref.read(chatNotifierProvider));
      return;
    }
    if (commandSource != 'local') {
      await _fail(
        command,
        code: 'invalid_source',
        message: 'The conversation source is invalid.',
      );
      return;
    }
    ref.read(chatNotifierProvider.notifier).cancelStreaming();
    await _succeed(command);
  }

  Future<void> _sendBoundCommandResult(
    WatchCommand command,
    RemoteCodingBoundCommandResult result, {
    required String action,
  }) {
    return switch (result.outcome) {
      RemoteCodingBoundCommandOutcome.accepted => _bridge.sendCommandResult(
        WatchCommandResult.success(
          id: command.id,
          code: 'accepted',
          message: '$action accepted by the desktop.',
        ),
      ),
      RemoteCodingBoundCommandOutcome.queued => _bridge.sendCommandResult(
        WatchCommandResult.success(
          id: command.id,
          code: 'queued',
          message: '$action queued on the desktop.',
        ),
      ),
      RemoteCodingBoundCommandOutcome.refused => _bridge.sendCommandResult(
        WatchCommandResult.failure(
          id: command.id,
          code: result.code.isEmpty ? 'remote_refused' : result.code,
          message: result.message.isEmpty
              ? 'The desktop refused the command.'
              : result.message,
        ),
      ),
      RemoteCodingBoundCommandOutcome.unknown => _bridge.sendCommandResult(
        WatchCommandResult.failure(
          id: command.id,
          code: result.code.isEmpty ? 'delivery_unknown' : result.code,
          message: result.message.isEmpty
              ? 'Delivery is unknown. Check the desktop before retrying.'
              : '${result.message} Check the desktop before retrying.',
        ),
      ),
    };
  }

  /// Answers a goal awaiting confirmation from the wrist.
  ///
  /// Routed through `markCurrentGoalStatus`, the same writer the phone's goal
  /// menu uses, rather than persisting a goal here. `validationStatus` already
  /// has three writers and the lesson from that is not to add a fourth shape
  /// of the same problem: a second path would drift from the transition rules
  /// in `ConversationGoalStatusTransition` the moment either side changed.
  Future<void> _handleResolveGoal(WatchCommand command) async {
    final completed = command.payload['completed'];
    if (completed is! bool) {
      await _fail(
        command,
        code: 'invalid_goal_decision',
        message: 'A goal decision must say completed true or false.',
      );
      return;
    }
    final conversations = ref.read(conversationsNotifierProvider);
    final current = conversations.currentConversation;
    // Stamped with the thread it was composed against, for the reason WATCH3
    // gave `sendMessage` the same check: `WatchSessionClient` falls back to
    // `transferUserInfo` when the phone is unreachable, which guarantees
    // delivery but not promptness. An unstamped decision would close whichever
    // goal happened to be current when it finally landed.
    final composedFor = (command.payload['conversationId'] as String?)?.trim();
    if (composedFor != null &&
        composedFor.isNotEmpty &&
        current != null &&
        composedFor != current.id) {
      await _fail(
        command,
        code: 'conversation_changed',
        message: 'That thread is no longer open.',
      );
      return;
    }
    final goal = current?.goal;
    // Refused rather than applied when the goal is not actually asking. The
    // frame the watch acted on may be several seconds old, and quietly closing
    // a goal that resumed in the meantime is exactly the stale-frame failure
    // the snapshot cursor exists to prevent.
    if (goal == null || !goal.isAwaitingConfirmation) {
      await _fail(
        command,
        code: 'goal_not_awaiting',
        message: 'That goal is no longer waiting for confirmation.',
      );
      return;
    }
    await ref
        .read(conversationsNotifierProvider.notifier)
        .markCurrentGoalStatus(
          status: completed
              ? ConversationGoalStatus.completed
              : ConversationGoalStatus.active,
          completionSummary: completed
              ? (goal.normalizedCompletionSummary ??
                    'Confirmed complete from Apple Watch.')
              : null,
        );
    await _succeed(command);
  }

  Future<void> _handleSelectConversation(WatchCommand command) async {
    final id = (command.payload['conversationId'] as String?)?.trim() ?? '';
    final conversations = ref.read(conversationsNotifierProvider);
    if (id.isEmpty ||
        !conversations.conversations.any(
          (conversation) => conversation.id == id,
        )) {
      await _fail(
        command,
        code: 'conversation_not_found',
        message: 'That thread no longer exists.',
      );
      return;
    }
    ref.read(conversationsNotifierProvider.notifier).selectConversation(id);
    await _succeed(command);
    await _pushSnapshot(ref.read(chatNotifierProvider));
  }

  Future<void> _handleResolveApproval(WatchCommand command) async {
    final approvalId = (command.payload['approvalId'] as String?)?.trim() ?? '';
    final approved = command.payload['approved'] == true;
    final pending = _currentApproval(ref.read(chatNotifierProvider));
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
    // Routed by the source the card carried, not by which notifier happens to
    // have something pending: answering a desktop's approval against this
    // phone's chat notifier resolves nothing and reports success.
    if (pending.source == WatchInteractionSource.remote) {
      await ref
          .read(remoteCodingClientProvider.notifier)
          .resolveApproval(approvalId: approvalId, approved: approved);
      await _succeed(command);
      await _pushSnapshot(ref.read(chatNotifierProvider));
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
    final shown = _currentQuestion(chatState);
    if (shown == null || shown.id != questionId) {
      await _fail(
        command,
        code: 'question_not_found',
        message: 'This question is no longer pending.',
      );
      return;
    }
    if (shown.source == WatchInteractionSource.remote) {
      await _resolveRemoteQuestion(command, questionId, shown);
      return;
    }
    final pending = chatState.pendingAskUserQuestion;
    if (pending == null || pending.id != questionId) {
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
            otherText: (command.payload['otherText'] as String?)?.trim() ?? '',
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
      WatchCommandResult.failure(id: command.id, code: code, message: message),
    );
    if (!ref.mounted) return;
    state = state.copyWith(lastError: message);
  }
}
