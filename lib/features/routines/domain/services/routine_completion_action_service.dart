import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../entities/routine.dart';

final routineCompletionActionServiceProvider =
    Provider<RoutineCompletionActionService>((ref) {
      return const RoutineCompletionActionService();
    });

class RoutineDeliveryDecision {
  const RoutineDeliveryDecision({
    required this.status,
    required this.message,
    this.payload,
  });

  final RoutineDeliveryStatus status;
  final String message;
  final String? payload;

  bool get shouldDeliver => payload != null;
}

class RoutineCompletionActionService {
  const RoutineCompletionActionService();

  RoutineDeliveryDecision planGoogleChatDelivery({
    required Routine routine,
    required RoutineRunRecord runRecord,
    required AppSettings settings,
  }) {
    if (!routine.postsToGoogleChat) {
      return const RoutineDeliveryDecision(
        status: RoutineDeliveryStatus.notRequested,
        message: 'Google Chat delivery is disabled for this routine.',
      );
    }

    if (!_matchesGoogleChatRule(routine.googleChatRule, runRecord)) {
      return RoutineDeliveryDecision(
        status: RoutineDeliveryStatus.skipped,
        message: _skipReasonForRule(routine.googleChatRule, runRecord),
      );
    }

    if (!settings.hasGoogleChatWebhook) {
      return const RoutineDeliveryDecision(
        status: RoutineDeliveryStatus.skipped,
        message: 'Google Chat webhook is not configured.',
      );
    }

    return RoutineDeliveryDecision(
      status: RoutineDeliveryStatus.notRequested,
      message: 'Ready to post to Google Chat.',
      payload: buildGoogleChatMessage(routine: routine, runRecord: runRecord),
    );
  }

  String buildGoogleChatMessage({
    required Routine routine,
    required RoutineRunRecord runRecord,
  }) {
    final buffer = StringBuffer();
    final outcome = runRecord.isSuccessful ? 'completed' : 'failed';
    final trigger = switch (runRecord.trigger) {
      RoutineRunTrigger.manual => 'manual',
      RoutineRunTrigger.scheduled => 'scheduled',
    };

    buffer.writeln('Routine "${routine.trimmedName}" $outcome.');
    buffer.writeln('Trigger: $trigger');
    buffer.writeln(
      'Finished: ${runRecord.finishedAt.toLocal().toIso8601String()}',
    );

    if (runRecord.usedTools) {
      final toolSummary = runRecord.toolNames.isEmpty
          ? '${runRecord.toolCallCount} tool call(s)'
          : runRecord.toolNames.join(', ');
      buffer.writeln('Tools: $toolSummary');
    }

    final summary = _summaryTextForRun(runRecord);
    if (summary.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Summary:');
      buffer.writeln(summary);
    }

    return buffer.toString().trim();
  }

  bool _matchesGoogleChatRule(
    RoutineGoogleChatRule rule,
    RoutineRunRecord runRecord,
  ) {
    return switch (rule) {
      RoutineGoogleChatRule.onSuccess => runRecord.isSuccessful,
      RoutineGoogleChatRule.onFailure => !runRecord.isSuccessful,
      RoutineGoogleChatRule.always => true,
    };
  }

  String _skipReasonForRule(
    RoutineGoogleChatRule rule,
    RoutineRunRecord runRecord,
  ) {
    if (rule == RoutineGoogleChatRule.always) {
      return 'Google Chat delivery was skipped.';
    }
    if (rule == RoutineGoogleChatRule.onSuccess && !runRecord.isSuccessful) {
      return 'Skipped Google Chat delivery because this rule posts only successful runs.';
    }
    if (rule == RoutineGoogleChatRule.onFailure && runRecord.isSuccessful) {
      return 'Skipped Google Chat delivery because this rule posts only failed runs.';
    }
    return 'Google Chat delivery was skipped.';
  }

  String _summaryTextForRun(RoutineRunRecord runRecord) {
    final candidates = [
      if (runRecord.isSuccessful) runRecord.preview.trim(),
      if (runRecord.isSuccessful && runRecord.output.trim().isNotEmpty)
        runRecord.output.trim(),
      if (!runRecord.isSuccessful) runRecord.error.trim(),
      if (!runRecord.isSuccessful && runRecord.preview.trim().isNotEmpty)
        runRecord.preview.trim(),
    ];

    for (final candidate in candidates) {
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return '';
  }
}
