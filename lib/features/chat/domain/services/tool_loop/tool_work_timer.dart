import '../../entities/conversation_work_time.dart';
import '../approval_wait_ledger.dart';

/// Turns a conversation's tool lifecycle transitions into tool work time.
///
/// Fed the same `started` / terminal transitions as `RunningToolTracker`, so
/// it needs no hook of its own in the tool loop. Lifecycle events carry a tool
/// name but no call id, so concurrent calls of one tool are paired first in,
/// first out. That can misattribute time between two such calls, but never
/// changes their total: it is the sum of end times minus the sum of starts.
final class ToolWorkTimer {
  ToolWorkTimer({
    required ApprovalWaitLedger approvals,
    DateTime Function() clock = DateTime.now,
  }) : _approvals = approvals,
       _clock = clock;

  final ApprovalWaitLedger _approvals;
  final DateTime Function() _clock;
  final Map<String, List<_ToolRun>> _runs = {};

  /// Applies one transition; reports a finished call to [sink].
  void track(
    String conversationId,
    String toolName,
    String lifecycleState, {
    ConversationWorkTimeSink? sink,
  }) {
    if (lifecycleState == 'queued') return;
    if (lifecycleState == 'started') {
      (_runs[conversationId] ??= []).add(
        _ToolRun(
          toolName,
          startedAt: _clock(),
          approvalWaitAtStartMs: _approvals.waitedMs(conversationId),
        ),
      );
      return;
    }
    final runs = _runs[conversationId];
    final index = runs?.indexWhere((run) => run.toolName == toolName) ?? -1;
    if (runs == null || index < 0) return;
    final run = runs.removeAt(index);
    if (runs.isEmpty) _runs.remove(conversationId);
    _report(conversationId, run, sink: sink, isError: false);
  }

  /// Ends every open call of [conversationId], for a turn torn down mid-tool.
  /// Booked as errors: the time was spent, but the calls never finished.
  void clear(String conversationId, {ConversationWorkTimeSink? sink}) {
    final runs = _runs.remove(conversationId);
    if (runs == null) return;
    for (final run in runs) {
      _report(conversationId, run, sink: sink, isError: true);
    }
  }

  void _report(
    String conversationId,
    _ToolRun run, {
    required ConversationWorkTimeSink? sink,
    required bool isError,
  }) {
    if (sink == null) return;
    final elapsedMs = _clock().difference(run.startedAt).inMilliseconds;
    final approvalMs =
        _approvals.waitedMs(conversationId) - run.approvalWaitAtStartMs;
    final workMs = elapsedMs - (approvalMs < 0 ? 0 : approvalMs);
    sink.record(
      conversationId: conversationId,
      kind: ConversationWorkKind.toolExecution,
      detail: run.toolName,
      durationMs: workMs < 0 ? 0 : workMs,
      isError: isError,
    );
  }
}

final class _ToolRun {
  const _ToolRun(
    this.toolName, {
    required this.startedAt,
    required this.approvalWaitAtStartMs,
  });

  final String toolName;
  final DateTime startedAt;
  final int approvalWaitAtStartMs;
}
