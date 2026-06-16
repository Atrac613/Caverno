import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/apple_foundation_models_datasource.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/live_llm_diagnostic.dart';
import '../../domain/services/live_llm_diagnostic_service.dart';
import '../../domain/services/model_capability_profile_builder.dart';
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

class ModelCapabilityAutoProbeNotifier
    extends Notifier<ModelCapabilityAutoProbeState> {
  static const autoProbeTimeout = Duration(seconds: 45);

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
    if (!force && settings.effectiveModelCapabilityProfile != null) {
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
    final service = LiveLlmDiagnosticService(
      settings: settings,
      chatDataSource: settings.llmProvider == LlmProvider.appleFoundationModels
          ? AppleFoundationModelsDataSource()
          : ref.read(chatRemoteDataSourceProvider),
      mcpToolService: ref.read(mcpToolServiceProvider),
    );

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
}
