import '../../../../core/types/assistant_mode.dart';
import '../providers/conversations_notifier.dart';

/// Applies an assistant-mode pick from the composer's mode menu.
///
/// Plan mode is the only mode that is a conversation property rather than a
/// setting, so it needs the split below: an already-started coding thread
/// switches immediately, while a thread that has not started yet only records
/// the preference and lets the first send open the planning session — picking
/// the mode must not navigate away from the new-thread screen mid-typing.
final class ComposerAssistantModeCoordinator {
  ComposerAssistantModeCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required Future<void> Function(AssistantMode mode) updateAssistantMode,
    required void Function() dismissPlanProposal,
  }) : _conversationsNotifier = conversationsNotifier,
       _updateAssistantMode = updateAssistantMode,
       _dismissPlanProposal = dismissPlanProposal;

  final ConversationsNotifier _conversationsNotifier;
  final Future<void> Function(AssistantMode mode) _updateAssistantMode;
  final void Function() _dismissPlanProposal;

  Future<void> select(
    AssistantMode mode, {
    required bool isCodingWorkspace,
    required bool hasConversation,
    required bool isPlanningSession,
  }) async {
    if (mode == AssistantMode.plan) {
      if (!isCodingWorkspace) return;
      if (!hasConversation) {
        await _updateAssistantMode(mode);
        return;
      }
      await _conversationsNotifier.enterPlanningSession();
      return;
    }

    if (isPlanningSession) {
      await _conversationsNotifier.exitPlanningSession();
      _dismissPlanProposal();
    }
    await _updateAssistantMode(mode);
  }
}
