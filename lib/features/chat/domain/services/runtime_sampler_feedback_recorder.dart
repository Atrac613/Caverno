// ChatNotifier decomposition collaborator: runtime-sampler-feedback-recorder

import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_sampler_preset_profile.dart';
import '../../../settings/domain/services/llm_sampler_runtime_feedback_service.dart';
import '../entities/chat_turn_owner.dart';
import 'model_edit_apply_telemetry_recorder.dart'
    show ModelCapabilityProfileStorePort, RuntimeSamplerFeedbackPort;

export 'model_edit_apply_telemetry_recorder.dart'
    show ModelCapabilityProfileStorePort, RuntimeSamplerFeedbackPort;

/// Receives immutable runtime sampler feedback events.
abstract interface class RuntimeSamplerFeedbackEventSink {
  Future<bool> recordEvent(RuntimeSamplerFeedbackEvent event);
}

/// Binds one immutable event to its recorder without capturing mutable owners.
final class RuntimeSamplerFeedbackEventBinding {
  const RuntimeSamplerFeedbackEventBinding({
    required this.sink,
    required this.event,
  });

  final RuntimeSamplerFeedbackEventSink sink;
  final RuntimeSamplerFeedbackEvent event;

  Future<void> record() async {
    await sink.recordEvent(event);
  }
}

/// Immutable owner and model-profile evidence shared by every feedback event.
sealed class RuntimeSamplerFeedbackEvent {
  RuntimeSamplerFeedbackEvent({
    required this.owner,
    required ModelCapabilityProfile baselineProfile,
  }) : baselineProfile = _freezeProfile(baselineProfile);

  final ChatTurnOwner owner;
  final ModelCapabilityProfile baselineProfile;
}

/// A tool failure that may describe a malformed model-emitted tool call.
final class RuntimeSamplerMalformedToolCallEvent
    extends RuntimeSamplerFeedbackEvent {
  RuntimeSamplerMalformedToolCallEvent({
    required super.owner,
    required super.baselineProfile,
    required this.message,
  });

  final String message;
}

/// A duplicate tool execution suppressed by the bounded tool loop.
final class RuntimeSamplerToolLoopRepetitionEvent
    extends RuntimeSamplerFeedbackEvent {
  RuntimeSamplerToolLoopRepetitionEvent({
    required super.owner,
    required super.baselineProfile,
  });
}

/// A repaired planning proposal using the settings-mode request mapping.
final class RuntimeSamplerPlanningJsonRepairEvent
    extends RuntimeSamplerFeedbackEvent {
  RuntimeSamplerPlanningJsonRepairEvent({
    required super.owner,
    required super.baselineProfile,
    required this.settingsLoaded,
    required this.assistantMode,
  });

  final bool settingsLoaded;
  final AssistantMode assistantMode;
}

/// A repaired JSON response for an explicitly selected request class.
final class RuntimeSamplerJsonRepairEvent extends RuntimeSamplerFeedbackEvent {
  RuntimeSamplerJsonRepairEvent({
    required super.owner,
    required super.baselineProfile,
    required this.requestClass,
  });

  final LlmSamplerRequestClass requestClass;
}

/// An already classified runtime sampler feedback signal.
final class RuntimeSamplerGenericSignalEvent
    extends RuntimeSamplerFeedbackEvent {
  RuntimeSamplerGenericSignalEvent({
    required super.owner,
    required super.baselineProfile,
    required LlmSamplerRuntimeFeedbackSignal signal,
  }) : signal = _freezeSignal(signal);

  final LlmSamplerRuntimeFeedbackSignal signal;
}

/// Best-effort owner-aware persistence for runtime sampler feedback.
final class RuntimeSamplerFeedbackRecorder
    implements RuntimeSamplerFeedbackPort, RuntimeSamplerFeedbackEventSink {
  const RuntimeSamplerFeedbackRecorder({
    required ModelCapabilityProfileStorePort profileStore,
    LlmSamplerRuntimeFeedbackService feedbackService =
        const LlmSamplerRuntimeFeedbackService(),
  }) : _profileStore = profileStore,
       _feedbackService = feedbackService;

  final ModelCapabilityProfileStorePort _profileStore;
  final LlmSamplerRuntimeFeedbackService _feedbackService;

  /// Records [event] without allowing telemetry failures into the chat loop.
  @override
  Future<bool> recordEvent(RuntimeSamplerFeedbackEvent event) async {
    try {
      final signal = _signalFor(event);
      if (signal == null) {
        return true;
      }
      final update = _feedbackService.recordSignal(
        profile: event.baselineProfile,
        signal: signal,
      );
      if (update == null) {
        return true;
      }
      await _profileStore.persist(owner: event.owner, profile: update.profile);
      return true;
    } on Object {
      // Runtime feedback must never interrupt the primary chat or tool loop.
      return false;
    }
  }

  @override
  Future<void> record({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile baselineProfile,
    required LlmSamplerRuntimeFeedbackSignal signal,
  }) async {
    try {
      await recordEvent(
        RuntimeSamplerGenericSignalEvent(
          owner: owner,
          baselineProfile: baselineProfile,
          signal: signal,
        ),
      );
    } on Object {
      // Event snapshotting is part of the same best-effort boundary.
    }
  }

  LlmSamplerRuntimeFeedbackSignal? _signalFor(
    RuntimeSamplerFeedbackEvent event,
  ) {
    return switch (event) {
      RuntimeSamplerMalformedToolCallEvent(:final message) =>
        LlmSamplerRuntimeFeedbackService.looksLikeMalformedToolCallFailure(
              message,
            )
            ? const LlmSamplerRuntimeFeedbackSignal(
                requestClass: LlmSamplerRequestClass.toolLoop,
                malformedToolCallCount: 1,
              )
            : null,
      RuntimeSamplerToolLoopRepetitionEvent() =>
        const LlmSamplerRuntimeFeedbackSignal(
          requestClass: LlmSamplerRequestClass.toolLoop,
          repetitionDetected: true,
        ),
      RuntimeSamplerPlanningJsonRepairEvent(
        :final settingsLoaded,
        :final assistantMode,
      ) =>
        settingsLoaded
            ? LlmSamplerRuntimeFeedbackSignal(
                requestClass: switch (assistantMode) {
                  AssistantMode.coding => LlmSamplerRequestClass.coding,
                  AssistantMode.plan => LlmSamplerRequestClass.plan,
                  AssistantMode.general => LlmSamplerRequestClass.toolLoop,
                },
                jsonRepairEventCount: 1,
              )
            : null,
      RuntimeSamplerJsonRepairEvent(:final requestClass) =>
        LlmSamplerRuntimeFeedbackSignal(
          requestClass: requestClass,
          jsonRepairEventCount: 1,
        ),
      RuntimeSamplerGenericSignalEvent(:final signal) => signal,
    };
  }
}

/// Reports a failed best-effort receipt to an outer telemetry transaction.
///
/// [ModelEditApplyTelemetryRecorder] catches this adapter's error and exposes
/// its existing typed `feedbackFailed` result without leaking into chat flow.
final class RuntimeSamplerFeedbackRequiredPort
    implements RuntimeSamplerFeedbackPort {
  const RuntimeSamplerFeedbackRequiredPort(this._recorder);

  final RuntimeSamplerFeedbackRecorder _recorder;

  @override
  Future<void> record({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile baselineProfile,
    required LlmSamplerRuntimeFeedbackSignal signal,
  }) async {
    final didSucceed = await _recorder.recordEvent(
      RuntimeSamplerGenericSignalEvent(
        owner: owner,
        baselineProfile: baselineProfile,
        signal: signal,
      ),
    );
    if (!didSucceed) {
      throw StateError('Runtime sampler feedback persistence failed');
    }
  }
}

ModelCapabilityProfile _freezeProfile(ModelCapabilityProfile source) {
  return source.copyWith(
    probeMetadata: Map<String, String>.unmodifiable(source.probeMetadata),
  );
}

LlmSamplerRuntimeFeedbackSignal _freezeSignal(
  LlmSamplerRuntimeFeedbackSignal source,
) {
  return LlmSamplerRuntimeFeedbackSignal(
    requestClass: source.requestClass,
    jsonRepairEventCount: source.jsonRepairEventCount,
    malformedToolCallCount: source.malformedToolCallCount,
    editApplyFailureCount: source.editApplyFailureCount,
    repetitionDetected: source.repetitionDetected,
  );
}
