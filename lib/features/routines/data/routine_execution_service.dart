import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/types/assistant_mode.dart';
import '../../chat/data/datasources/chat_datasource.dart';
import '../../chat/domain/entities/message.dart';
import '../../chat/domain/services/system_prompt_builder.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../settings/domain/entities/app_settings.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/entities/routine.dart';
import '../domain/services/routine_schedule_service.dart';

final routineExecutionServiceProvider = Provider<RoutineExecutionService>((
  ref,
) {
  return RoutineExecutionService(
    dataSource: ref.watch(chatRemoteDataSourceProvider),
    settings: ref.watch(settingsNotifierProvider),
  );
});

class RoutineExecutionService {
  RoutineExecutionService({
    required ChatDataSource dataSource,
    required AppSettings settings,
  }) : _dataSource = dataSource,
       _settings = settings;

  final ChatDataSource _dataSource;
  final AppSettings _settings;
  final Uuid _uuid = const Uuid();

  Future<RoutineRunRecord> execute(
    Routine routine, {
    RoutineRunTrigger trigger = RoutineRunTrigger.manual,
  }) async {
    final startedAt = DateTime.now();

    try {
      final systemPrompt = SystemPromptBuilder.build(
        now: startedAt,
        assistantMode: AssistantMode.general,
        languageCode: _resolveLanguageCode(),
      );

      final result = await _dataSource.createChatCompletion(
        messages: [
          Message(
            id: 'routine_system',
            content: systemPrompt,
            role: MessageRole.system,
            timestamp: startedAt,
          ),
          Message(
            id: 'routine_user',
            content: routine.trimmedPrompt,
            role: MessageRole.user,
            timestamp: startedAt,
          ),
        ],
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      final output = RoutineScheduleService.truncateOutput(result.content);
      final preview = RoutineScheduleService.summarizeOutput(output);
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(startedAt).inMilliseconds;

      if (output.isEmpty) {
        return RoutineRunRecord(
          id: _uuid.v4(),
          startedAt: startedAt,
          finishedAt: finishedAt,
          status: RoutineRunStatus.failed,
          trigger: trigger,
          durationMs: durationMs,
          preview: 'Routine completed without any visible output.',
          error: 'Routine completed without any visible output.',
        );
      }

      return RoutineRunRecord(
        id: _uuid.v4(),
        startedAt: startedAt,
        finishedAt: finishedAt,
        status: RoutineRunStatus.completed,
        trigger: trigger,
        durationMs: durationMs,
        preview: preview,
        output: output,
      );
    } catch (error) {
      final finishedAt = DateTime.now();
      final durationMs = finishedAt.difference(startedAt).inMilliseconds;
      final message = error.toString().trim();

      return RoutineRunRecord(
        id: _uuid.v4(),
        startedAt: startedAt,
        finishedAt: finishedAt,
        status: RoutineRunStatus.failed,
        trigger: trigger,
        durationMs: durationMs,
        preview: message,
        error: message,
      );
    }
  }

  String _resolveLanguageCode() {
    final preference = _settings.language.trim().toLowerCase();
    if (preference == 'ja' || preference == 'en') {
      return preference;
    }
    return 'en';
  }
}
