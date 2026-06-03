import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/mcp_tool_provider.dart';
import '../../domain/entities/live_llm_diagnostic.dart';
import '../../domain/services/live_llm_diagnostic_service.dart';
import 'settings_notifier.dart';

final liveLlmDiagnosticNotifierProvider =
    NotifierProvider<LiveLlmDiagnosticNotifier, LiveLlmDiagnosticState>(
      LiveLlmDiagnosticNotifier.new,
    );

class LiveLlmDiagnosticNotifier extends Notifier<LiveLlmDiagnosticState> {
  int _generation = 0;

  @override
  LiveLlmDiagnosticState build() => LiveLlmDiagnosticState.initial;

  Future<void> run() async {
    final generation = ++_generation;
    state = state.copyWith(isRunning: true, clearError: true);
    final service = LiveLlmDiagnosticService(
      settings: ref.read(settingsNotifierProvider),
      chatDataSource: ref.read(chatRemoteDataSourceProvider),
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
      state = state.copyWith(
        isRunning: false,
        report: report,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = state.copyWith(isRunning: false, error: error.toString());
    }
  }
}
