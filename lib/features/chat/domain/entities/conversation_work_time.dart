/// What kind of work a conversation spent time on.
///
/// The split exists to answer "where did this session's time go": waiting on
/// the model, doing work on this machine, or waiting on the user. Approval
/// waits are their own kind because a tool call blocked on an approval sheet
/// is not machine work, and folding it into [toolExecution] would let one
/// unattended sheet dominate the figure.
enum ConversationWorkKind {
  /// Wall-clock time of LLM requests, from issue to the last streamed chunk.
  llmInference,

  /// Foreground tool calls run by a turn, minus time spent awaiting approval.
  toolExecution,

  /// Background jobs started with `process_start`, from launch to exit.
  backgroundProcess,

  /// Time a turn sat blocked on an approval sheet.
  approvalWait;

  static ConversationWorkKind? fromName(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// Receives finished units of work for per-conversation time accounting.
///
/// Implementations must never throw and never block the caller, for the same
/// reason as `ModelUsageSink`: accounting is bookkeeping, and failing to write
/// it must not break a turn.
abstract interface class ConversationWorkTimeSink {
  /// [detail] narrows [kind]: the usage role for LLM requests, the tool name
  /// for tool calls, and empty where there is nothing finer to report.
  void record({
    required String conversationId,
    required ConversationWorkKind kind,
    required int durationMs,
    String detail = '',
    bool isError = false,
  });
}

/// One accumulated (kind, detail) bucket of a conversation.
class ConversationWorkTimeEntry {
  const ConversationWorkTimeEntry({
    required this.kind,
    required this.detail,
    required this.count,
    required this.durationMs,
    this.errorCount = 0,
  });

  final ConversationWorkKind kind;
  final String detail;
  final int count;
  final int errorCount;
  final int durationMs;
}

/// A conversation's accumulated work time, grouped for display.
class ConversationWorkTimeSummary {
  ConversationWorkTimeSummary(Iterable<ConversationWorkTimeEntry> entries)
    : entries = List<ConversationWorkTimeEntry>.unmodifiable(entries);

  static final empty = ConversationWorkTimeSummary(
    const <ConversationWorkTimeEntry>[],
  );

  final List<ConversationWorkTimeEntry> entries;

  bool get isEmpty => entries.every((entry) => entry.count == 0);

  int durationMsOf(ConversationWorkKind kind) => entries
      .where((entry) => entry.kind == kind)
      .fold(0, (total, entry) => total + entry.durationMs);

  int countOf(ConversationWorkKind kind) => entries
      .where((entry) => entry.kind == kind)
      .fold(0, (total, entry) => total + entry.count);

  /// Buckets of [kind], longest first, with an empty [detail] last.
  List<ConversationWorkTimeEntry> breakdownOf(ConversationWorkKind kind) =>
      entries.where((entry) => entry.kind == kind).toList()
        ..sort((a, b) => b.durationMs.compareTo(a.durationMs));

  /// The summary with [extraMs] of still-running work added under [kind],
  /// so a live job counts before it has finished and been recorded.
  ConversationWorkTimeSummary withLive(
    ConversationWorkKind kind, {
    required int extraMs,
    required int extraCount,
  }) {
    if (extraMs <= 0 && extraCount <= 0) return this;
    return ConversationWorkTimeSummary([
      ...entries,
      ConversationWorkTimeEntry(
        kind: kind,
        detail: 'running',
        count: extraCount,
        durationMs: extraMs,
      ),
    ]);
  }
}
