import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/running_tool_tracker.dart';

/// Which tools each thread's turn is running right now, keyed by conversation.
///
/// Deliberately not a `ChatState` field: this is transient per-thread progress
/// with no bearing on the transcript, and keeping it here avoids threading it
/// through `ThreadScopedChatState`'s stash-and-restore. The notifier takes no
/// dependencies, so any `ProviderScope` can read it — including widget tests
/// that never build a `ChatNotifier`.
final runningToolsProvider =
    NotifierProvider<RunningToolsNotifier, Map<String, List<String>>>(
      RunningToolsNotifier.new,
    );

class RunningToolsNotifier extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() => const <String, List<String>>{};

  /// Tools [conversationId]'s turn has started and not yet finished.
  List<String> forConversation(String? conversationId) => conversationId == null
      ? const <String>[]
      : state[conversationId] ?? const <String>[];

  /// Applies one tool-execution lifecycle transition.
  ///
  /// A null [conversationId] means the generation has no live turn to attribute
  /// the tool to, which happens on teardown races; there is nothing to record.
  void track(String? conversationId, String toolName, String lifecycleState) {
    if (conversationId == null) return;
    final current = state[conversationId] ?? const <String>[];
    final next = RunningToolTracker.next(
      current,
      toolName: toolName,
      lifecycleState: lifecycleState,
    );
    if (next == null) return;
    final updated = Map<String, List<String>>.of(state);
    if (next.isEmpty) {
      updated.remove(conversationId);
    } else {
      updated[conversationId] = next;
    }
    state = updated;
  }

  /// Drops everything recorded for [conversationId].
  ///
  /// A turn killed mid-tool never receives that tool's `completed` event, so
  /// without this the name would outlive the turn and the status row would
  /// keep announcing it.
  void clear(String conversationId) {
    if (!state.containsKey(conversationId)) return;
    state = {...state}..remove(conversationId);
  }
}
