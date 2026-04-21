import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/domain/services/routine_completion_action_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  Routine buildRoutine({
    RoutineCompletionAction completionAction = RoutineCompletionAction.none,
    RoutineGoogleChatRule googleChatRule = RoutineGoogleChatRule.onFailure,
  }) {
    return Routine(
      id: 'routine-1',
      name: 'Morning summary',
      prompt: 'Summarize the latest updates.',
      createdAt: DateTime(2026, 4, 21, 8),
      updatedAt: DateTime(2026, 4, 21, 8),
      completionAction: completionAction,
      googleChatRule: googleChatRule,
    );
  }

  RoutineRunRecord buildRunRecord({
    RoutineRunStatus status = RoutineRunStatus.completed,
    RoutineRunTrigger trigger = RoutineRunTrigger.scheduled,
  }) {
    return RoutineRunRecord(
      id: 'run-1',
      startedAt: DateTime(2026, 4, 21, 9),
      finishedAt: DateTime(2026, 4, 21, 9, 0, 4),
      status: status,
      trigger: trigger,
      preview: status == RoutineRunStatus.completed
          ? 'Morning summary is ready.'
          : 'Routine failed during execution.',
      error: status == RoutineRunStatus.failed
          ? 'Routine failed during execution.'
          : '',
      toolCallCount: 1,
      toolNames: const ['web_search'],
      usedTools: true,
    );
  }

  group('RoutineCompletionActionService', () {
    const service = RoutineCompletionActionService();

    test('returns notRequested when Google Chat delivery is disabled', () {
      final decision = service.planGoogleChatDelivery(
        routine: buildRoutine(),
        runRecord: buildRunRecord(),
        settings: AppSettings.defaults(),
      );

      expect(decision.shouldDeliver, isFalse);
      expect(decision.status, RoutineDeliveryStatus.notRequested);
      expect(decision.message, contains('disabled'));
    });

    test('returns skipped when the Google Chat rule does not match', () {
      final decision = service.planGoogleChatDelivery(
        routine: buildRoutine(
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.onFailure,
        ),
        runRecord: buildRunRecord(status: RoutineRunStatus.completed),
        settings: AppSettings.defaults().copyWith(
          googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        ),
      );

      expect(decision.shouldDeliver, isFalse);
      expect(decision.status, RoutineDeliveryStatus.skipped);
      expect(decision.message, contains('only failed runs'));
    });

    test('returns skipped when the webhook is missing', () {
      final decision = service.planGoogleChatDelivery(
        routine: buildRoutine(
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.always,
        ),
        runRecord: buildRunRecord(),
        settings: AppSettings.defaults(),
      );

      expect(decision.shouldDeliver, isFalse);
      expect(decision.status, RoutineDeliveryStatus.skipped);
      expect(decision.message, 'Google Chat webhook is not configured.');
    });

    test('builds a payload when the rule matches and the webhook exists', () {
      final decision = service.planGoogleChatDelivery(
        routine: buildRoutine(
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.always,
        ),
        runRecord: buildRunRecord(),
        settings: AppSettings.defaults().copyWith(
          googleChatWebhookUrl: 'https://chat.googleapis.com/v1/spaces/test',
        ),
      );

      expect(decision.shouldDeliver, isTrue);
      expect(decision.payload, isNotNull);
      expect(
        decision.payload,
        contains('Routine "Morning summary" completed.'),
      );
      expect(decision.payload, contains('Trigger: scheduled'));
      expect(decision.payload, contains('Tools: web_search'));
      expect(decision.payload, contains('Morning summary is ready.'));
    });
  });
}
