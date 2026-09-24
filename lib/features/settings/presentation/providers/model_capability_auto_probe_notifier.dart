import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';

import '../../../chat/data/datasources/openai_modalities_probe.dart';
import '../../../chat/data/datasources/reasoning_effort_probe.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/live_llm_diagnostic.dart';
import '../../domain/services/live_llm_diagnostic_service.dart';
import '../../domain/services/model_capability_profile_builder.dart';
import 'live_llm_diagnostic_notifier.dart';
import 'model_context_window_resolver.dart';
import 'settings_notifier.dart';

final modelCapabilityAutoProbeNotifierProvider =
    NotifierProvider<
      ModelCapabilityAutoProbeNotifier,
      ModelCapabilityAutoProbeState
    >(ModelCapabilityAutoProbeNotifier.new);

enum ModelCapabilityAutoProbeStatus {
  idle,
  running,
  skipped,
  succeeded,
  failed,
}

class ModelCapabilityAutoProbeState {
  const ModelCapabilityAutoProbeState({
    this.status = ModelCapabilityAutoProbeStatus.idle,
    this.profileId = '',
    this.report,
    this.error = '',
  });

  final ModelCapabilityAutoProbeStatus status;
  final String profileId;
  final LiveLlmDiagnosticReport? report;
  final String error;

  static const initial = ModelCapabilityAutoProbeState();

  bool get isRunning => status == ModelCapabilityAutoProbeStatus.running;

  ModelCapabilityAutoProbeState copyWith({
    ModelCapabilityAutoProbeStatus? status,
    String? profileId,
    LiveLlmDiagnosticReport? report,
    String? error,
  }) {
    return ModelCapabilityAutoProbeState(
      status: status ?? this.status,
      profileId: profileId ?? this.profileId,
      report: report ?? this.report,
      error: error ?? this.error,
    );
  }
}

/// HTTP client used for the token-free modality read, overridable in tests.
final modalitiesProbeClientProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

/// HTTP client used for the reasoning-effort probe, overridable in tests.
///
/// Separate from [modalitiesProbeClientProvider] because this one reaches
/// `/chat/completions`: a test that stubs `/props` must not have its stub
/// answer generation requests as well.
final reasoningEffortProbeClientProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

class ModelCapabilityAutoProbeNotifier
    extends Notifier<ModelCapabilityAutoProbeState> {
  static const autoProbeTimeout = Duration(seconds: 45);

  final Set<String> _videoBackfillAttempted = <String>{};

  @override
  ModelCapabilityAutoProbeState build() =>
      ModelCapabilityAutoProbeState.initial;

  Future<void> runForCurrentModel({
    bool force = false,
    String source = 'probe',
  }) async {
    final settings = ref.read(settingsNotifierProvider);
    final profileId = ModelCapabilityProfile.buildId(
      provider: settings.llmProvider,
      baseUrl: settings.baseUrl,
      model: settings.effectiveModel,
    );
    if (state.isRunning && state.profileId == profileId) {
      return;
    }
    if (settings.demoMode || settings.effectiveModel.trim().isEmpty) {
      state = ModelCapabilityAutoProbeState(
        status: ModelCapabilityAutoProbeStatus.skipped,
        profileId: profileId,
      );
      return;
    }
    final storedProfile = settings.effectiveModelCapabilityProfile;
    if (!force && storedProfile != null) {
      // Profiles stored before the context window was measured carry 0. Backfill
      // it from the endpoint rather than forcing a full re-probe: the catalog
      // lookup is a plain HTTP read, so this costs no LLM tokens.
      await _backfillContextWindow(settings, storedProfile);
      if (!ref.mounted) return;
      await _backfillVideoInputSupport(settings, storedProfile);
      if (!ref.mounted) return;
      state = ModelCapabilityAutoProbeState(
        status: ModelCapabilityAutoProbeStatus.skipped,
        profileId: profileId,
        report: state.report,
      );
      return;
    }

    state = ModelCapabilityAutoProbeState(
      status: ModelCapabilityAutoProbeStatus.running,
      profileId: profileId,
    );
    final service = createLiveLlmDiagnosticService(ref, settings);

    try {
      final report = await service
          .run(probeIds: LiveLlmDiagnosticService.modelCapabilityProbeIds)
          .timeout(autoProbeTimeout);
      if (!ref.mounted) {
        return;
      }
      await ref
          .read(settingsNotifierProvider.notifier)
          .upsertModelCapabilityProfile(
            ModelCapabilityProfileBuilder.fromLiveDiagnosticReport(
              report: report,
              provider: settings.llmProvider,
              usableContextTokens: await resolveUsableContextTokens(
                ref,
                settings,
              ),
            ),
            source: source,
          );
      if (!ref.mounted) {
        return;
      }
      state = ModelCapabilityAutoProbeState(
        status: ModelCapabilityAutoProbeStatus.succeeded,
        profileId: profileId,
        report: report,
      );
      await _probeReasoningEfforts(
        settings,
        profileId: profileId,
        previous: storedProfile?.supportedReasoningEfforts,
      );
    } catch (error) {
      if (!ref.mounted) {
        return;
      }
      state = ModelCapabilityAutoProbeState(
        status: ModelCapabilityAutoProbeStatus.failed,
        profileId: profileId,
        error: error.toString(),
      );
    }
  }

  /// Measures which reasoning efforts the endpoint accepts for this model.
  ///
  /// Runs only on this path, after a full probe, because it spends real
  /// completions (one baseline plus one per effort, each capped at a single
  /// token). Profiles that predate it are measured at the next model switch or
  /// idle re-probe. The profile was just rebuilt from the diagnostic report, so
  /// an inconclusive run restores [previous] rather than erasing a vocabulary
  /// an earlier probe did establish.
  Future<void> _probeReasoningEfforts(
    AppSettings settings, {
    required String profileId,
    required List<String>? previous,
  }) async {
    if (settings.llmProvider != LlmProvider.openAiCompatible) return;
    final client = ref.read(reasoningEffortProbeClientProvider)();
    final ReasoningEffortProbeResult result;
    try {
      result = await const ReasoningEffortProbe().run(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
        model: settings.effectiveModel,
        acceptsChatTemplateKwargs: settings.acceptsChatTemplateKwargsFor(
          settings.baseUrl,
        ),
        candidates: reasoningEffortProbeCandidates,
        client: client,
      );
    } finally {
      client.close();
    }
    if (!ref.mounted) return;
    // By id, not the effective profile: the person may have switched models
    // while the probe ran, and this result belongs to the one it measured.
    final stored = ref
        .read(settingsNotifierProvider)
        .modelCapabilityProfiles
        .where((profile) => profile.id == profileId)
        .firstOrNull;
    if (stored == null) return;
    await ref
        .read(settingsNotifierProvider.notifier)
        .upsertModelCapabilityProfile(
          stored.copyWith(
            supportedReasoningEfforts: result.isConclusive
                ? result.accepted
                : previous,
            probeMetadata: {
              ...stored.probeMetadata,
              'reasoningEffortProbe': result.outcome,
            },
          ),
          source: 'reasoning_effort_probe',
        );
  }

  /// Every effort the app can send, in the order the composer lists them.
  static final List<String> reasoningEffortProbeCandidates = [
    for (final effort in ReasoningEffortPreference.values) ?effort.apiValue,
  ];

  /// Fills in a stored profile's context window when it was never measured.
  /// A profile that already carries one is left alone: re-measuring belongs to
  /// a real probe, where drift detection can act on it.
  /// Fills in the video modality for a profile stored before it was measured.
  ///
  /// Same reasoning as [_backfillContextWindow]: without this, every profile
  /// that already existed stays at [ModelVideoInputSupport.unknown] forever,
  /// because a stored profile short-circuits the auto-probe and only a forced
  /// run rewrites it. The person would have to know to re-run diagnostics to
  /// see a composer button appear, which is not a thing anyone would guess.
  ///
  /// Costs no tokens: asking the endpoint what it accepts is one HTTP read.
  /// Resolves the video modality for the active model if it is still unknown.
  ///
  /// Safe to call from a widget that needs the answer to render: it is
  /// idempotent, never starts a generation run, and does nothing at all once
  /// the profile has one. Nothing calls the auto-probe at launch -- it fires on
  /// a model switch or a settings screen -- so without a caller like that, a
  /// capability added after a profile was written is never resolved for
  /// somebody who simply opens the app and keeps using the model they had.
  Future<void> ensureVideoInputSupport() async {
    final settings = ref.read(settingsNotifierProvider);
    final storedProfile = settings.effectiveModelCapabilityProfile;
    if (storedProfile == null) return;
    await _backfillVideoInputSupport(settings, storedProfile);
  }

  Future<void> _backfillVideoInputSupport(
    AppSettings settings,
    ModelCapabilityProfile storedProfile,
  ) async {
    if (storedProfile.videoInputSupport != ModelVideoInputSupport.unknown) {
      return;
    }
    // One read per profile per session. The composer asks on every build of a
    // fresh conversation, and the answer does not change under us.
    if (!_videoBackfillAttempted.add(storedProfile.id)) return;
    final client = ref.read(modalitiesProbeClientProvider)();
    final EndpointModalitySupport support;
    try {
      support = await const OpenAiModalitiesProbe().videoSupport(
        baseUrl: settings.baseUrl,
        model: settings.effectiveModel,
        client: client,
        headers: ApiConstants.userAgentHeaders,
      );
    } finally {
      client.close();
    }
    // Silence leaves the profile alone: unknown is what it already says, and
    // rewriting it would only churn the revision history.
    if (support == EndpointModalitySupport.unknown || !ref.mounted) return;
    await ref
        .read(settingsNotifierProvider.notifier)
        .upsertModelCapabilityProfile(
          storedProfile.copyWith(
            videoInputSupport: support == EndpointModalitySupport.supported
                ? ModelVideoInputSupport.supported
                : ModelVideoInputSupport.unsupported,
          ),
          source: 'video_modality_backfill',
        );
  }

  Future<void> _backfillContextWindow(
    AppSettings settings,
    ModelCapabilityProfile storedProfile,
  ) async {
    if (storedProfile.usableContextTokens > 0) return;
    final tokens = await resolveUsableContextTokens(ref, settings);
    if (tokens <= 0 || !ref.mounted) return;
    await ref
        .read(settingsNotifierProvider.notifier)
        .upsertModelCapabilityProfile(
          storedProfile.copyWith(usableContextTokens: tokens),
          source: 'context_backfill',
        );
  }
}
