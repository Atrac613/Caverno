import '../../../../core/types/assistant_mode.dart';

/// Which assistant mode the composer shows.
///
/// Plan mode is a property of the conversation, not of settings: a stored
/// [AssistantMode.plan] preference resolves to coding inside a normal coding
/// thread, mirroring `ChatNotifier._resolveAssistantMode`.
///
/// The exception is a coding thread that has not started yet. There the stored
/// preference is a *pending* selection that the first send turns into a
/// planning session, so the composer keeps showing Plan instead of snapping
/// back to Coding and making the selection look ignored.
class ComposerAssistantModeResolver {
  const ComposerAssistantModeResolver._();

  static AssistantMode resolve({
    required AssistantMode settingsMode,
    required bool isPlanningSession,
    required bool isCodingWorkspace,
    required bool hasConversation,
  }) {
    if (isPlanningSession) return AssistantMode.plan;
    if (settingsMode != AssistantMode.plan) return settingsMode;
    if (!isCodingWorkspace) return AssistantMode.general;
    return hasConversation ? AssistantMode.coding : AssistantMode.plan;
  }
}
