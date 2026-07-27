import '../../domain/entities/tool_call_info.dart';

/// Tool results and executed commands accumulated during an assistant turn.
///
/// Extracted from ChatNotifier, where the same three fields were read by the
/// prompt builders, the completion-claim guards and the goal auto-continue
/// evidence. Holding them together keeps their lifecycle in one place: the two
/// result lists are always cleared as a pair, and every consumer that wants
/// "everything this turn ran" wants [all] rather than either list alone.
///
/// The state is deliberately turn-scoped, not conversation-scoped. Two
/// responses can be in flight at once (a detached background turn plus the
/// visible one), so a single flat ledger hands one turn the other's results.
/// Keying by interaction generation is the fix that follows this extraction.
class TurnToolResultLedger {
  List<ToolResultInfo> _completed = const [];
  final List<ToolResultInfo> _content = <ToolResultInfo>[];
  final List<String> _commands = <String>[];
  int? _commandGeneration;

  /// Results from the tool-calling loop, replaced wholesale per turn.
  List<ToolResultInfo> get completed => _completed;

  /// Results from `<tool_call>` blocks parsed out of streamed content, which
  /// accumulate across the continuations within a single turn.
  List<ToolResultInfo> get content =>
      List<ToolResultInfo>.unmodifiable(_content);

  /// Commands issued through command-execution tools during the current
  /// interaction generation. Repair revivals re-enter the batch executor with a
  /// fresh result list, so the transcript claim guard needs the ledger to
  /// survive a revival while still resetting on the next user message.
  List<String> get commands => List<String>.unmodifiable(_commands);

  /// Everything the turn produced, loop results before content results.
  List<ToolResultInfo> get all =>
      List<ToolResultInfo>.unmodifiable([..._completed, ..._content]);

  void setCompleted(Iterable<ToolResultInfo> results) {
    _completed = List<ToolResultInfo>.unmodifiable(results);
  }

  void addContentResult(ToolResultInfo result) {
    _content.add(result);
  }

  /// The most recent content result matching [test], newest first.
  ToolResultInfo? lastContentResultWhere(bool Function(ToolResultInfo) test) {
    for (final result in _content.reversed) {
      if (test(result)) return result;
    }
    return null;
  }

  void clearResults() {
    _completed = const [];
    _content.clear();
  }

  void clearContentResults() {
    _content.clear();
  }

  /// Snapshots [all] and clears both result lists.
  List<ToolResultInfo> takeAll() {
    final snapshot = all;
    clearResults();
    return snapshot;
  }

  /// Resets the command ledger when the turn advances. Called for every tool
  /// result, not only command executions, so the reset does not depend on the
  /// new turn happening to start with a command.
  void beginCommandGeneration(int generation) {
    if (_commandGeneration == generation) return;
    _commandGeneration = generation;
    _commands.clear();
  }

  void recordCommand(String command) {
    _commands.add(command);
  }
}
