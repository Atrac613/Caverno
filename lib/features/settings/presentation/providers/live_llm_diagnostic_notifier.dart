import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/apple_foundation_models_datasource.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../data/live_llm_benchmark_artifact_file_service.dart';
import '../../data/live_llm_diagnostic_history_repository.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/live_llm_diagnostic.dart';
import '../../domain/services/live_llm_diagnostic_service.dart';
import '../../domain/services/model_capability_profile_builder.dart';
import 'model_context_window_resolver.dart';
import 'settings_notifier.dart';

final liveLlmDiagnosticNotifierProvider =
    NotifierProvider<LiveLlmDiagnosticNotifier, LiveLlmDiagnosticState>(
      LiveLlmDiagnosticNotifier.new,
    );

class LiveLlmDiagnosticNotifier extends Notifier<LiveLlmDiagnosticState> {
  int _generation = 0;
  late final LiveLlmDiagnosticHistoryRepository _historyRepository;

  @override
  LiveLlmDiagnosticState build() {
    _historyRepository = LiveLlmDiagnosticHistoryRepository(
      ref.read(sharedPreferencesProvider),
    );
    return LiveLlmDiagnosticState(
      history: _historyRepository
          .load()
          .map((entry) => entry.report)
          .toList(growable: false),
    );
  }

  Future<void> run() async {
    final generation = ++_generation;
    state = state.copyWith(isRunning: true, clearError: true);
    final settings = ref.read(settingsNotifierProvider);
    final service = LiveLlmDiagnosticService(
      settings: settings,
      chatDataSource: settings.llmProvider == LlmProvider.appleFoundationModels
          ? AppleFoundationModelsDataSource()
          : ref.read(chatRemoteDataSourceProvider),
      mcpToolService: ref.read(mcpToolServiceProvider),
    );

    try {
      final report = await service.run(
        onReport: (report) {
          if (!ref.mounted || generation != _generation) {
            return;
          }
          state = state.copyWith(report: report, clearError: true);
        },
      );
      if (!ref.mounted || generation != _generation) {
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
            source: 'calibrate',
          );
      if (!ref.mounted || generation != _generation) {
        return;
      }
      final history = await _historyRepository.append(report);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(
        isRunning: false,
        report: report,
        history: history.map((entry) => entry.report).toList(growable: false),
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(isRunning: false, error: error.toString());
    }
  }

  /// Imports physical and bounded evidence produced by the headless LL39
  /// canary, then persists it through the same LL21 revision path as an in-app
  /// calibration.
  Future<bool> importBenchmarkArtifact() async {
    final settings = ref.read(settingsNotifierProvider);
    final profile = await ref
        .read(liveLlmBenchmarkArtifactFileServiceProvider)
        .importProfile(existingProfiles: settings.modelCapabilityProfiles);
    if (profile == null) return false;
    await ref
        .read(settingsNotifierProvider.notifier)
        .upsertModelCapabilityProfile(profile, source: 'benchmark_artifact');
    return true;
  }
}
