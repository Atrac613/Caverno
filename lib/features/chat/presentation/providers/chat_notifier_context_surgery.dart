// Same-library extension for LL14 context observation state updates.
//
// Riverpod marks `ref` as `@protected`, which is not aware of extensions even
// in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierContextSurgery on ChatNotifier {
  Set<String> _contextSurgeryProtectedPaths() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) return const <String>{};
    final task = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );
    if (task == null) return const <String>{};
    return task.targetFiles
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  void _updateContextSurgeryObservation({
    String? systemPrompt,
    List<ToolResultInfo>? toolResults,
  }) {
    if (!ref.mounted) return;
    if (systemPrompt != null) {
      _latestObservedSystemPrompt = systemPrompt;
    }
    if (toolResults != null) {
      _latestObservedToolResults = List<ToolResultInfo>.unmodifiable(
        toolResults,
      );
    }
    final snapshot = ContextSurgeryObservationService.buildSnapshot(
      systemPrompt: _latestObservedSystemPrompt,
      toolResults: _latestObservedToolResults,
    );
    if (state.contextSurgerySnapshot == snapshot) return;
    state = state.copyWith(contextSurgerySnapshot: snapshot);
  }
}
