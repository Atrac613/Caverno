import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/model_capability_profile_store_runtime_adapter.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/model_edit_apply_telemetry_recorder.dart';
import '../../domain/services/runtime_sampler_feedback_recorder.dart';

/// Connects owner-aware edit telemetry to settings persistence.
final class ModelEditApplyTelemetryRuntimeAdapter {
  ModelEditApplyTelemetryRuntimeAdapter(SettingsNotifier settings) {
    _profileStore = OwnerValidatedModelCapabilityProfileStoreAdapter(
      persistence: _SettingsModelCapabilityProfilePersistence(settings),
    );
    _runtimeSamplerFeedback = RuntimeSamplerFeedbackRecorder(
      profileStore: _profileStore,
    );
    _recorder = ModelEditApplyTelemetryRecorder(
      profileStore: _profileStore,
      runtimeFeedback: RuntimeSamplerFeedbackRequiredPort(
        _runtimeSamplerFeedback,
      ),
    );
  }

  late final OwnerValidatedModelCapabilityProfileStoreAdapter _profileStore;
  late final RuntimeSamplerFeedbackRecorder _runtimeSamplerFeedback;
  late final ModelEditApplyTelemetryRecorder _recorder;
  int _detachedRuntimeFeedbackGeneration = 0;

  RuntimeSamplerFeedbackEventSink get runtimeSamplerFeedback =>
      _runtimeSamplerFeedback;

  ModelCapabilityProfile baselineFor(AppSettings settings) =>
      ModelEditApplyTelemetryBaseline.resolve(
        effectiveProfile: settings.effectiveModelCapabilityProfile,
        provider: settings.llmProvider,
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
      );

  void activateOwner(ChatTurnOwner owner) => _profileStore.activateOwner(owner);

  ChatTurnOwner activateDetachedRuntimeFeedbackOwner(String scope) {
    final normalizedScope = scope.trim();
    final owner = ChatTurnOwner(
      conversationId:
          'runtime-sampler-feedback:'
          '${normalizedScope.isEmpty ? 'global' : normalizedScope}',
      interactionGeneration: ++_detachedRuntimeFeedbackGeneration,
    );
    _profileStore.activateOwner(owner);
    return owner;
  }

  void retireOwner(ChatTurnOwner owner) => _profileStore.retireOwner(owner);

  bool isCurrent(ChatTurnOwner owner) => _profileStore.isCurrent(owner);

  void clear() => _profileStore.clear();

  Future<ModelEditApplyTelemetryRecordResult> record({
    required ChatTurnOwner owner,
    required ToolResultInfo toolResult,
    required ModelCapabilityProfile baselineProfile,
  }) => _recorder.record(
    owner: owner,
    toolResult: toolResult,
    baselineProfile: baselineProfile,
  );
}

final class _SettingsModelCapabilityProfilePersistence
    implements ModelCapabilityProfilePersistencePort {
  const _SettingsModelCapabilityProfilePersistence(this._settings);

  final SettingsNotifier _settings;

  @override
  Future<void> persist(ModelCapabilityProfile profile) =>
      _settings.upsertModelCapabilityProfile(profile);
}
