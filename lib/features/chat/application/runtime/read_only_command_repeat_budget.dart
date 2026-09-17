import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_call_execution_policy.dart';

/// Bounds how often one read-only command may run again within a turn.
///
/// [ToolCallExecutionPolicy.shouldAllowRepeatedToolExecution] admits read-only
/// command calls so a model that lost an earlier command's output can fetch it
/// again. It has to: a follow-up request carries only the current batch's
/// results, and `ToolLoopContextDigest` names a command and its exit status
/// without its output, telling the model to "run it again only when you need
/// its output again". Before this budget the duplicate guard discarded exactly
/// that re-run — session 96e27118 asked for a release, ran
/// `git tag --list --sort=-version:refname` at loop 5, lost the tag list by
/// loop 7, re-issued the identical command, and the skip left the batch empty
/// and ended the turn one sentence into the work with no notice.
///
/// Admitting the repeat unbounded would trade a dead turn for a spinning one,
/// so each distinct call gets [maxExecutionsPerKey] executions. The key carries
/// the same generations as [ToolCallExecutionPolicy.toolExecutionKey]: a write
/// or a mutating command hands the command a fresh budget, because after the
/// workspace moves the same observation is a different question rather than a
/// repeat.
///
/// Only read-only commands are counted. A mutating command still collides with
/// its own earlier key in the duplicate guard, which is what keeps one side
/// effect from running twice.
final class ReadOnlyCommandRepeatBudget {
  ReadOnlyCommandRepeatBudget({
    ToolCallExecutionPolicy executionPolicy = const ToolCallExecutionPolicy(),
  }) : _executionPolicy = executionPolicy;

  /// Executions allowed per distinct call per generation: the original plus one
  /// re-run to recover output the follow-up request did not carry.
  static const int maxExecutionsPerKey = 2;

  final ToolCallExecutionPolicy _executionPolicy;
  final Map<String, int> _executionsByKey = <String, int>{};
  int? _interactionGeneration;

  /// Binds the budget to one batch's generations, so the per-call questions
  /// asked inside the batch loop are one argument each.
  ReadOnlyCommandRepeatBudgetScope forBatch({
    required int interactionGeneration,
    required int commandRetryGeneration,
    required int stateChangeGeneration,
  }) {
    _resetForInteraction(interactionGeneration);
    return ReadOnlyCommandRepeatBudgetScope._(
      this,
      commandRetryGeneration,
      stateChangeGeneration,
    );
  }

  String? _keyFor(
    ToolCallInfo toolCall, {
    required int commandRetryGeneration,
    required int stateChangeGeneration,
    ProjectPathResolver? resolveProjectPath,
  }) {
    if (!_executionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
      return null;
    }
    // Narration is stripped for the same reason the failure key strips it: a
    // reworded `reason` is the same command, and a budget it can reset is no
    // budget at all.
    final semanticKey = _executionPolicy.toolCallDedupKey(
      toolCall.name,
      toolCall.arguments,
      resolveProjectPath: resolveProjectPath,
      excludeNonSemanticKeys: true,
    );
    return '$commandRetryGeneration:$stateChangeGeneration:$semanticKey';
  }

  void _resetForInteraction(int interactionGeneration) {
    if (_interactionGeneration == interactionGeneration) {
      return;
    }
    _interactionGeneration = interactionGeneration;
    _executionsByKey.clear();
  }
}

/// One batch's view of a [ReadOnlyCommandRepeatBudget].
final class ReadOnlyCommandRepeatBudgetScope {
  const ReadOnlyCommandRepeatBudgetScope._(
    this._budget,
    this._commandRetryGeneration,
    this._stateChangeGeneration,
  );

  final ReadOnlyCommandRepeatBudget _budget;
  final int _commandRetryGeneration;
  final int _stateChangeGeneration;

  /// Whether [toolCall] has already used its whole budget.
  ///
  /// False for anything that is not a read-only command, so the caller can ask
  /// unconditionally and leave every other tool to the duplicate guard.
  bool isExhausted(ToolCallInfo toolCall) {
    final key = _keyFor(toolCall);
    if (key == null) {
      return false;
    }
    return (_budget._executionsByKey[key] ?? 0) >=
        ReadOnlyCommandRepeatBudget.maxExecutionsPerKey;
  }

  /// Counts one scheduled execution of [toolCall].
  ///
  /// Called when the loop decides to run the call rather than when it returns,
  /// so a command that never answers still spends its budget.
  void recordExecution(ToolCallInfo toolCall) {
    final key = _keyFor(toolCall);
    if (key == null) {
      return;
    }
    _budget._executionsByKey[key] = (_budget._executionsByKey[key] ?? 0) + 1;
  }

  String? _keyFor(ToolCallInfo toolCall) => _budget._keyFor(
    toolCall,
    commandRetryGeneration: _commandRetryGeneration,
    stateChangeGeneration: _stateChangeGeneration,
  );
}
