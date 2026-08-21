import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/lan_endpoint_discovery.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/services/local_llm_autodetect_service.dart';

/// The wizard's pages, in order.
enum OnboardingStep { welcome, language, theme, connect, model, done }

final localLlmAutodetectServiceProvider = Provider<LocalLlmAutodetectService>((
  ref,
) {
  return LocalLlmAutodetectService(ref.watch(lanEndpointDiscoveryProvider));
});

/// Loopback detection results for the connect step.
///
/// Starts empty rather than auto-running: the step triggers [detect] when it is
/// first shown, so a user who restores from a backup never pays for the probe.
class LoopbackDetectionNotifier
    extends Notifier<AsyncValue<List<DiscoveredEndpoint>>> {
  @override
  AsyncValue<List<DiscoveredEndpoint>> build() =>
      const AsyncValue.data(<DiscoveredEndpoint>[]);

  bool _started = false;

  /// Probe loopback once. Repeat calls are ignored unless [force] is set.
  Future<void> detect({bool force = false}) async {
    if (_started && !force) return;
    _started = true;
    state = const AsyncValue.loading();
    final endpoints = await ref
        .read(localLlmAutodetectServiceProvider)
        .probeLoopback();
    state = AsyncValue.data(endpoints);
  }
}

final loopbackDetectionProvider =
    NotifierProvider<
      LoopbackDetectionNotifier,
      AsyncValue<List<DiscoveredEndpoint>>
    >(LoopbackDetectionNotifier.new);

/// How the user is supplying the connection on the connect step.
enum OnboardingConnectionMode { detected, manual }

class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.welcome,
    this.connectionMode = OnboardingConnectionMode.detected,
    this.endpoint,
    this.manualBaseUrl = '',
    this.manualApiKey = '',
    this.manualVerified = false,
    this.selectedModel = '',
    this.availableModels = const <String>[],
    this.restored = false,
  });

  final OnboardingStep step;
  final OnboardingConnectionMode connectionMode;

  /// The detected endpoint the user picked, when [connectionMode] is
  /// [OnboardingConnectionMode.detected].
  final DiscoveredEndpoint? endpoint;

  final String manualBaseUrl;
  final String manualApiKey;

  /// Whether the manual endpoint answered a connection test. Advancing on an
  /// untested endpoint is what leaves users at a chat page that 400s.
  final bool manualVerified;

  final String selectedModel;

  /// Models the connection step already learned about — detection and the
  /// manual connection test both read `/v1/models` to decide the endpoint is
  /// real, so the model step has no reason to ask again.
  final List<String> availableModels;

  /// Set when settings were imported from a backup, which makes the connection
  /// steps redundant.
  final bool restored;

  bool get isManual => connectionMode == OnboardingConnectionMode.manual;

  /// Base URL the later steps should read models from.
  String get baseUrl =>
      isManual ? manualBaseUrl.trim() : (endpoint?.baseUrl ?? '');

  /// Discovery probes are unauthenticated by design, so a detected local
  /// server carries no key; local servers accept the placeholder.
  String get apiKey =>
      isManual ? manualApiKey.trim() : ApiConstants.defaultApiKey;

  bool get hasConnection => isManual ? manualVerified : endpoint != null;

  /// Whether the Next button is live on the current step.
  bool get canAdvance => switch (step) {
    OnboardingStep.welcome => true,
    OnboardingStep.language => true,
    OnboardingStep.theme => true,
    OnboardingStep.connect => hasConnection,
    OnboardingStep.model => selectedModel.trim().isNotEmpty,
    OnboardingStep.done => true,
  };

  OnboardingState copyWith({
    OnboardingStep? step,
    OnboardingConnectionMode? connectionMode,
    DiscoveredEndpoint? endpoint,
    String? manualBaseUrl,
    String? manualApiKey,
    bool? manualVerified,
    String? selectedModel,
    List<String>? availableModels,
    bool? restored,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      connectionMode: connectionMode ?? this.connectionMode,
      endpoint: endpoint ?? this.endpoint,
      manualBaseUrl: manualBaseUrl ?? this.manualBaseUrl,
      manualApiKey: manualApiKey ?? this.manualApiKey,
      manualVerified: manualVerified ?? this.manualVerified,
      selectedModel: selectedModel ?? this.selectedModel,
      availableModels: availableModels ?? this.availableModels,
      restored: restored ?? this.restored,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void next() {
    final steps = OnboardingStep.values;
    final index = steps.indexOf(state.step);
    if (index >= steps.length - 1) return;
    state = state.copyWith(step: steps[index + 1]);
  }

  void back() {
    final steps = OnboardingStep.values;
    final index = steps.indexOf(state.step);
    if (index <= 0) return;
    state = state.copyWith(step: steps[index - 1]);
  }

  /// Jump straight to the closing step, used after a successful restore.
  void skipToDone() {
    state = state.copyWith(step: OnboardingStep.done, restored: true);
  }

  void selectEndpoint(DiscoveredEndpoint endpoint) {
    state = state.copyWith(
      connectionMode: OnboardingConnectionMode.detected,
      endpoint: endpoint,
      selectedModel: endpoint.modelIds.isEmpty ? '' : endpoint.modelIds.first,
      availableModels: endpoint.modelIds,
    );
  }

  void useManualEntry() {
    state = state.copyWith(connectionMode: OnboardingConnectionMode.manual);
  }

  void useDetectedEntry() {
    state = state.copyWith(connectionMode: OnboardingConnectionMode.detected);
  }

  /// Record manual connection edits. Any edit invalidates a previous test:
  /// the verified flag must describe the values currently on screen.
  void updateManualConnection({String? baseUrl, String? apiKey}) {
    state = state.copyWith(
      manualBaseUrl: baseUrl ?? state.manualBaseUrl,
      manualApiKey: apiKey ?? state.manualApiKey,
      manualVerified: false,
      availableModels: const <String>[],
    );
  }

  void markManualVerified({required List<String> models}) {
    state = state.copyWith(
      manualVerified: true,
      selectedModel: models.isEmpty ? '' : models.first,
      availableModels: models,
    );
  }

  void selectModel(String modelId) {
    state = state.copyWith(selectedModel: modelId);
  }

  /// Persist the chosen connection and close onboarding.
  ///
  /// A restore already wrote a full settings object, so the wizard must not
  /// overwrite it with the defaults it never asked the user about.
  Future<void> complete() async {
    final settings = ref.read(settingsNotifierProvider.notifier);
    final current = state;

    if (!current.restored && current.hasConnection) {
      final baseUrl = current.baseUrl;
      final apiKey = current.apiKey;
      final model = current.selectedModel.trim();
      final detected = current.endpoint;

      await settings.upsertLlmEndpoint(
        LlmEndpoint(
          id: '',
          label: detected == null
              ? baseUrl
              : '${detected.serverHint} (${detected.host})',
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          source: detected == null
              ? LlmEndpointSource.manual
              : LlmEndpointSource.discovered,
        ),
        dedupeByBaseUrl: true,
      );
      await settings.updateBaseUrl(baseUrl);
      await settings.updateApiKey(apiKey);
      if (model.isNotEmpty) {
        await settings.updateModel(model);
      }
    }

    await settings.completeOnboarding();
  }
}

final onboardingNotifierProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
      OnboardingNotifier.new,
    );
