// Same-library extension for tool-result observation and profile telemetry.
//
// Riverpod marks `ref` as `@protected`, which is not aware of extensions even
// in the same library.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

const _contentToolFailureFormatter = ContentToolFailureFormatter();

extension ChatNotifierToolResultTelemetry on ChatNotifier {
  ModelCapabilityProfile _modelEditApplyTelemetryBaseline() =>
      _modelEditTelemetry!.baselineFor(_settings);

  RuntimeSamplerFeedbackEventBinding? _planningJsonRepairFeedbackBinding() {
    final telemetry = _modelEditTelemetry;
    if (telemetry == null) return null;
    final activeGeneration = _activeResponseGenerationForConversation(
      conversationId,
    );
    final activeOwner = activeGeneration == null
        ? null
        : _turnOwnerForGeneration(activeGeneration);
    final owner =
        activeOwner ??
        telemetry.activateDetachedRuntimeFeedbackOwner(
          conversationId ?? 'global',
        );
    return RuntimeSamplerFeedbackEventBinding(
      sink: telemetry.runtimeSamplerFeedback,
      event: RuntimeSamplerPlanningJsonRepairEvent(
        owner: owner,
        baselineProfile: _modelEditApplyTelemetryBaseline(),
        settingsLoaded: _hasLoadedSettings,
        assistantMode: _settings.assistantMode,
      ),
    );
  }

  Future<void> _recordModelEditApplyTelemetry(
    ChatTurnOwner owner,
    ToolResultInfo toolResult, {
    required ModelCapabilityProfile baselineProfile,
  }) async {
    final telemetry = _modelEditTelemetry;
    if (telemetry == null) return;
    final result = await telemetry.record(
      owner: owner,
      toolResult: toolResult,
      baselineProfile: baselineProfile,
    );
    if (!result.didPersist ||
        !ref.mounted ||
        !telemetry.isCurrent(owner)) {
      return;
    }
    _settings = ref.read(settingsNotifierProvider);
  }
}
