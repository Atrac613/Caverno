import 'dart:async';

import '../../entities/chat_turn_owner.dart';
import '../../entities/conversation_work_time.dart';

/// Measures how long each conversation's turns sat blocked on approvals.
///
/// Tool execution time is measured around the whole tool call, and an
/// approval sheet is shown from inside that call. Without subtracting the
/// wait, one sheet left open over lunch would read as an hour of machine work.
/// The running-tool tracker reads [waitedMs] at a tool's start and end and
/// takes the difference out.
///
/// Process-wide by default ([shared]) because the approval registry is owned
/// by `ChatNotifier`, whose library is at its line ratchet; the registry
/// reaches the ledger without the notifier having to wire it.
final class ApprovalWaitLedger {
  ApprovalWaitLedger({DateTime Function() clock = DateTime.now})
    : _clock = clock;

  static final shared = ApprovalWaitLedger();

  final DateTime Function() _clock;
  final Map<String, ({String conversationId, DateTime openedAt})> _open = {};
  final Map<String, int> _closedMsByConversation = {};

  /// Where finished waits are booked; null records nothing.
  ConversationWorkTimeSink? sink;

  /// Times approval [requestId] from now until [completer] settles.
  ///
  /// Keyed to the completer rather than to registry removal because every
  /// way out -- answered, cancelled, or cleared with its owner -- completes
  /// it, while removal has several paths that would each have to report.
  void track(
    String requestId,
    ChatTurnOwner owner,
    Completer<Object?> completer,
  ) {
    opened(requestId, owner.conversationId);
    void close() => closed(requestId);
    unawaited(
      completer.future.then((_) => close(), onError: (_, _) => close()),
    );
  }

  /// Starts timing approval [requestId] raised by [conversationId]'s turn.
  void opened(String requestId, String conversationId) {
    _open.putIfAbsent(
      requestId,
      () => (conversationId: conversationId, openedAt: _clock()),
    );
  }

  /// Stops timing [requestId]. Idempotent, so every exit path may call it.
  void closed(String requestId) {
    final open = _open.remove(requestId);
    if (open == null) return;
    final waitedMs = _clock().difference(open.openedAt).inMilliseconds;
    final elapsed = waitedMs < 0 ? 0 : waitedMs;
    _closedMsByConversation.update(
      open.conversationId,
      (total) => total + elapsed,
      ifAbsent: () => elapsed,
    );
    sink?.record(
      conversationId: open.conversationId,
      kind: ConversationWorkKind.approvalWait,
      durationMs: elapsed,
    );
  }

  /// Total approval wait of [conversationId] so far, open waits included.
  int waitedMs(String conversationId) {
    final now = _clock();
    var total = _closedMsByConversation[conversationId] ?? 0;
    for (final open in _open.values) {
      if (open.conversationId != conversationId) continue;
      total += now.difference(open.openedAt).inMilliseconds;
    }
    return total;
  }
}
