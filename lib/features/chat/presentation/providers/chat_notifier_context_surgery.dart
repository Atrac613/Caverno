// Same-library extension for LL14 context observation state updates.
//
// Riverpod marks `ref` as `@protected`, which is not aware of extensions even
// in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierContextSurgery on ChatNotifier {
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
