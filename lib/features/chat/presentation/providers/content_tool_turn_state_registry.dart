import '../../domain/entities/chat_turn_owner.dart';

/// Immutable view of content-tool orchestration state for one turn owner.
final class ContentToolTurnStateSnapshot {
  ContentToolTurnStateSnapshot._(_ContentToolTurnState state)
    : executedCallKeys = Set<String>.unmodifiable(state.executedCallKeys),
      seenCallHashes = Set<String>.unmodifiable(state.seenCallHashes),
      pendingResults = List<String>.unmodifiable(state.pendingResults),
      pendingExecutionCount = state.pendingExecutions.length,
      continuationFallback = state.continuationFallback,
      continuationCount = state.continuationCount;

  final Set<String> executedCallKeys;
  final Set<String> seenCallHashes;
  final List<String> pendingResults;
  final int pendingExecutionCount;
  final String? continuationFallback;
  final int continuationCount;
}

/// Owns content-tool state for explicitly registered assistant turns.
///
/// Mutations never create state. Call [begin] once a turn has an owner, then
/// [dispose] when the turn reaches a terminal state. Disposed owners are
/// rejected by later writes and cannot be begun again in this registry.
final class ContentToolTurnStateRegistry {
  final Map<ChatTurnOwner, _ContentToolTurnState> _states =
      <ChatTurnOwner, _ContentToolTurnState>{};
  final Map<String, int> _disposedGenerationWatermarks = <String, int>{};

  int get length => _states.length;
  bool get isEmpty => _states.isEmpty;

  bool contains(ChatTurnOwner owner) => _states.containsKey(owner);

  bool begin(ChatTurnOwner owner) {
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= disposedThrough ||
        _states.containsKey(owner)) {
      return false;
    }
    _states[owner] = _ContentToolTurnState();
    return true;
  }

  ContentToolTurnStateSnapshot? snapshot(ChatTurnOwner owner) {
    final state = _states[owner];
    return state == null ? null : ContentToolTurnStateSnapshot._(state);
  }

  bool markSeenCall(ChatTurnOwner owner, String hash) {
    final state = _states[owner];
    return state != null && state.seenCallHashes.add(hash);
  }

  bool hasSeenCall(ChatTurnOwner owner, String hash) =>
      _states[owner]?.seenCallHashes.contains(hash) ?? false;

  bool markExecutedCall(ChatTurnOwner owner, String key) {
    final state = _states[owner];
    return state != null && state.executedCallKeys.add(key);
  }

  bool hasExecutedCall(ChatTurnOwner owner, String key) =>
      _states[owner]?.executedCallKeys.contains(key) ?? false;

  bool addPendingResult(ChatTurnOwner owner, String result) {
    final state = _states[owner];
    if (state == null) return false;
    state.pendingResults.add(result);
    return true;
  }

  int pendingResultCount(ChatTurnOwner owner) =>
      _states[owner]?.pendingResults.length ?? 0;

  List<String> pendingResults(ChatTurnOwner owner) => List<String>.unmodifiable(
    _states[owner]?.pendingResults ?? const <String>[],
  );

  List<String> takePendingResults(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null || state.pendingResults.isEmpty) {
      return const <String>[];
    }
    final results = List<String>.unmodifiable(state.pendingResults);
    state.pendingResults.clear();
    return results;
  }

  bool setContinuationFallback(ChatTurnOwner owner, String? fallback) {
    final state = _states[owner];
    if (state == null) return false;
    state.continuationFallback = fallback;
    return true;
  }

  String? continuationFallback(ChatTurnOwner owner) =>
      _states[owner]?.continuationFallback;

  int continuationCount(ChatTurnOwner owner) =>
      _states[owner]?.continuationCount ?? 0;

  int? incrementContinuationCount(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null) return null;
    state.continuationCount += 1;
    return state.continuationCount;
  }

  bool resetContinuationCount(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null) return false;
    state.continuationCount = 0;
    return true;
  }

  int pendingExecutionCount(ChatTurnOwner owner) =>
      _states[owner]?.pendingExecutions.length ?? 0;

  /// Enqueues [execute] after earlier executions owned by the same turn.
  ///
  /// The returned future preserves execution failures for the caller. The
  /// internal tail absorbs a failure so a later execution can still run.
  Future<void>? enqueueExecution(
    ChatTurnOwner owner,
    Future<void> Function() execute,
  ) {
    final state = _states[owner];
    if (state == null) return null;

    final execution = state.executionTail.then((_) {
      if (!identical(_states[owner], state)) {
        return Future<void>.value();
      }
      return execute();
    });
    state.executionTail = execution.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    state.pendingExecutions.add(execution);
    return execution;
  }

  /// Takes the current pending batch and waits for every execution in it.
  ///
  /// Executions enqueued while the batch is draining remain pending for the
  /// next drain. Failures are propagated after the batch settles.
  Future<int> drainPendingExecutions(ChatTurnOwner owner) async {
    final state = _states[owner];
    if (state == null || state.pendingExecutions.isEmpty) return 0;

    final pending = List<Future<void>>.of(state.pendingExecutions);
    state.pendingExecutions.clear();
    await Future.wait(pending);
    return pending.length;
  }

  bool dispose(ChatTurnOwner owner) {
    final removed = _states.remove(owner) != null;
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration > disposedThrough) {
      _disposedGenerationWatermarks[owner.conversationId] =
          owner.interactionGeneration;
    }
    return removed;
  }

  void clear() {
    for (final owner in _states.keys.toList(growable: false)) {
      dispose(owner);
    }
  }
}

final class _ContentToolTurnState {
  final Set<String> executedCallKeys = <String>{};
  final Set<String> seenCallHashes = <String>{};
  final List<String> pendingResults = <String>[];
  final List<Future<void>> pendingExecutions = <Future<void>>[];
  Future<void> executionTail = Future<void>.value();
  String? continuationFallback;
  int continuationCount = 0;
}
