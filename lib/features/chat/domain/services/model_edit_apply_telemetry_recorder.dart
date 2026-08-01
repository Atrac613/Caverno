import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_sampler_preset_profile.dart';
import '../../../settings/domain/services/llm_sampler_runtime_feedback_service.dart';
import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'model_edit_apply_telemetry_service.dart';

// ChatNotifier decomposition collaborator: model-edit-apply-telemetry-recorder

/// Persists one profile update for the exact turn that produced it.
///
/// Implementations should reject stale owners by throwing. A successful
/// completion means the profile is safe to use as the baseline for follow-up
/// telemetry.
abstract interface class ModelCapabilityProfileStorePort {
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  });
}

/// Records runtime sampler feedback without consulting mutable turn state.
abstract interface class RuntimeSamplerFeedbackPort {
  Future<void> record({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile baselineProfile,
    required LlmSamplerRuntimeFeedbackSignal signal,
  });
}

/// Builds the explicit baseline captured by a notifier adapter.
abstract final class ModelEditApplyTelemetryBaseline {
  static ModelCapabilityProfile resolve({
    required ModelCapabilityProfile? effectiveProfile,
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    return effectiveProfile ??
        ModelCapabilityProfile(
          id: '',
          provider: provider,
          baseUrl: baseUrl,
          model: model,
        ).normalizedForPersistence();
  }
}

enum ModelEditApplyTelemetryRecordStatus {
  noUpdate,
  persisted,
  persistedWithFeedback,
  updateFailed,
  persistenceFailed,
  feedbackFailed,
}

/// Best-effort result returned so adapters can refresh owner-independent state.
final class ModelEditApplyTelemetryRecordResult {
  const ModelEditApplyTelemetryRecordResult._({
    required this.status,
    required this.observation,
    required this.persistedProfile,
  });

  const ModelEditApplyTelemetryRecordResult.noUpdate()
    : this._(
        status: ModelEditApplyTelemetryRecordStatus.noUpdate,
        observation: null,
        persistedProfile: null,
      );

  const ModelEditApplyTelemetryRecordResult.updateFailed()
    : this._(
        status: ModelEditApplyTelemetryRecordStatus.updateFailed,
        observation: null,
        persistedProfile: null,
      );

  const ModelEditApplyTelemetryRecordResult.persistenceFailed({
    required ModelEditApplyObservation observation,
  }) : this._(
         status: ModelEditApplyTelemetryRecordStatus.persistenceFailed,
         observation: observation,
         persistedProfile: null,
       );

  const ModelEditApplyTelemetryRecordResult.persisted({
    required ModelEditApplyObservation observation,
    required ModelCapabilityProfile profile,
  }) : this._(
         status: ModelEditApplyTelemetryRecordStatus.persisted,
         observation: observation,
         persistedProfile: profile,
       );

  const ModelEditApplyTelemetryRecordResult.persistedWithFeedback({
    required ModelEditApplyObservation observation,
    required ModelCapabilityProfile profile,
  }) : this._(
         status: ModelEditApplyTelemetryRecordStatus.persistedWithFeedback,
         observation: observation,
         persistedProfile: profile,
       );

  const ModelEditApplyTelemetryRecordResult.feedbackFailed({
    required ModelEditApplyObservation observation,
    required ModelCapabilityProfile profile,
  }) : this._(
         status: ModelEditApplyTelemetryRecordStatus.feedbackFailed,
         observation: observation,
         persistedProfile: profile,
       );

  final ModelEditApplyTelemetryRecordStatus status;
  final ModelEditApplyObservation? observation;
  final ModelCapabilityProfile? persistedProfile;

  bool get didPersist => persistedProfile != null;
}

/// Classifies and records edit-apply telemetry for one immutable turn owner.
final class ModelEditApplyTelemetryRecorder {
  const ModelEditApplyTelemetryRecorder({
    required ModelCapabilityProfileStorePort profileStore,
    required RuntimeSamplerFeedbackPort runtimeFeedback,
  }) : _profileStore = profileStore,
       _runtimeFeedback = runtimeFeedback;

  final ModelCapabilityProfileStorePort _profileStore;
  final RuntimeSamplerFeedbackPort _runtimeFeedback;

  Future<ModelEditApplyTelemetryRecordResult> record({
    required ChatTurnOwner owner,
    required ToolResultInfo toolResult,
    required ModelCapabilityProfile baselineProfile,
  }) async {
    ModelEditApplyObservation? observation;
    ModelCapabilityProfile? updatedProfile;
    try {
      observation = ModelEditApplyTelemetryService.classifyToolResult(
        toolResult,
      );
      updatedProfile = ModelEditApplyTelemetryService.recordToolResult(
        profile: baselineProfile,
        toolResult: toolResult,
      );
    } catch (_) {
      return const ModelEditApplyTelemetryRecordResult.updateFailed();
    }

    if (observation == null || updatedProfile == null) {
      return const ModelEditApplyTelemetryRecordResult.noUpdate();
    }

    try {
      await _profileStore.persist(owner: owner, profile: updatedProfile);
    } catch (_) {
      return ModelEditApplyTelemetryRecordResult.persistenceFailed(
        observation: observation,
      );
    }

    if (!observation.isFailure) {
      return ModelEditApplyTelemetryRecordResult.persisted(
        observation: observation,
        profile: updatedProfile,
      );
    }

    try {
      await _runtimeFeedback.record(
        owner: owner,
        baselineProfile: updatedProfile,
        signal: const LlmSamplerRuntimeFeedbackSignal(
          requestClass: LlmSamplerRequestClass.toolLoop,
          editApplyFailureCount: 1,
        ),
      );
    } catch (_) {
      return ModelEditApplyTelemetryRecordResult.feedbackFailed(
        observation: observation,
        profile: updatedProfile,
      );
    }
    return ModelEditApplyTelemetryRecordResult.persistedWithFeedback(
      observation: observation,
      profile: updatedProfile,
    );
  }
}
